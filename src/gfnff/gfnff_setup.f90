! This file is part of xtb.
!
! Copyright (C) 2019-2020 Stefan Grimme
!
! xtb is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! xtb is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with xtb.  If not, see <https://www.gnu.org/licenses/>.

module xtb_gfnff_setup
  use xtb_gfnff_ini, only : gfnff_ini
  use xtb_gfnff_data, only : TGFFData
  use xtb_gfnff_topology, only : TGFFTopology
  use xtb_gfnff_generator, only : TGFFGenerator
  implicit none
  private
  public :: gfnff_setup, gfnff_input

contains

subroutine gfnff_setup(env,verbose,restart,mol,p_ext_gfnff,gen,param,topo)
  use iso_fortran_env
  use xtb_restart
  use xtb_type_environment, only : TEnvironment
  use xtb_type_molecule, only : TMolecule
  use xtb_gfnff_param, only : ini, gfnff_set_param
  use xtb_setparam, only : ichrg
  implicit none
! Dummy
  !integer,intent(in) :: ich
  type(TGFFTopology), intent(inout) :: topo
  type(TGFFGenerator), intent(inout) :: gen
  type(TGFFData), intent(inout) :: param
  integer,intent(in) :: p_ext_gfnff
  logical,intent(in) :: restart
  logical,intent(in) :: verbose
  type(TMolecule)  :: mol
  type(TEnvironment), intent(inout) :: env
  !type(TGFFTopology), intent(inout) :: topo
! Stack
  logical            :: ex
  logical            :: success

  call gfnff_input(env, mol, topo)
  call gfnff_set_param(mol%n, gen, param)
  if (restart) then
     inquire(file='gfnff_topo', exist=ex)
     if (ex) then
       call read_restart_gff('gfnff_topo',mol%n,p_ext_gfnff,success,.true.,topo)
       !hbrefgeo is usually set within gfnff_ini2/gfnff_hbset0 equal to initial xyz
       topo%hbrefgeo=mol%xyz
       if (success) write(*,'(10x,"GFN-FF topology read from file successfully!")')
       if (.not.success) then
          write(*,'(10x,"GFN-FF topology read in did not work!")')
          write(*,'(10x,"Generating new topology file!")')
          call gfnff_ini(verbose,ini,mol,ichrg,gen,param,topo)
          call write_restart_gff('gfnff_topo',mol%n,p_ext_gfnff,topo)
       end if
     else
       call gfnff_ini(verbose,ini,mol,ichrg,gen,param,topo)
       if (.not.mol%struc%two_dimensional) then
          call write_restart_gff('gfnff_topo',mol%n,p_ext_gfnff,topo)
       end if
     end if
  else if (.not.restart) then
     call gfnff_ini(verbose,ini,mol,ichrg,gen,param,topo)
     call write_restart_gff('gfnff_topo',mol%n,p_ext_gfnff,topo)
  end if

end subroutine gfnff_setup

subroutine gfnff_input(env, mol, topo)
  use xtb_mctc_accuracy, only : wp
  use xtb_type_environment, only : TEnvironment
  use xtb_type_molecule
  use xtb_mctc_filetypes, only : fileType
  use xtb_gfnff_param
  use xtb_setparam, only : ichrg
  implicit none
  ! Dummy
  type(TMolecule),intent(in) :: mol
  type(TEnvironment), intent(inout) :: env
  type(TGFFTopology), intent(inout) :: topo
  ! Stack
  integer           :: i,j,k
  integer           :: ni
  integer           :: ns
  integer           :: nf
  integer           :: ich
  integer           :: iatom
  integer           :: iresidue
  integer           :: ifrag
  integer           :: ibond
  integer           :: bond_ij(2)
  real(wp)          :: r
  real(wp)          :: dum1
  real(wp)          :: floats(10)
  logical           :: ex
  character(len=80) :: atmp
  character(len=80) :: s(10)

  if (.not.allocated(topo%nb))       allocate( topo%nb(20,mol%n), source = 0 )
  if (.not.allocated(topo%qfrag))    allocate( topo%qfrag(mol%n), source = 0.0d0 )
  if (.not.allocated(topo%fraglist)) allocate( topo%fraglist(mol%n), source = 0 )
  if (.not.allocated(topo%q))        allocate( topo%q(mol%n), source = 0.0d0 )

  !write(*,*) 'test' , mol%ftype

  !if (allocated(mol%pdb)) then
  !  read_file_type = 2
  !  ini = .true.
  !else if (allocated(mol%sdf)) then
  !  read_file_type = 1
  !  ini = .false.
  !else
  !  read_file_type = 0
  !  ini = .true.
  !end if

  select case(mol%ftype)
  !--------------------------------------------------------------------
  ! PDB case
  case(fileType%pdb)
    !write(*,*) 'PDB' , mol%ftype
    ini = .true.
    ifrag=0
    associate(rn => mol%pdb%residue_number, qatom => mol%pdb%charge)
      do iresidue = minval(rn),maxval(rn)
        if (any(iresidue .eq. rn)) then
          ifrag=ifrag+1
          where(iresidue .eq. rn) topo%fraglist = ifrag
        end if
      end do
      topo%nfrag = maxval(topo%fraglist)
      do iatom=1,mol%n
        topo%qfrag(topo%fraglist(iatom)) = topo%qfrag(topo%fraglist(iatom)) + dble(qatom(iatom))
      end do
      topo%qpdb = qatom
    end associate
    ichrg=idint(sum(topo%qfrag(1:topo%nfrag)))
    write(*,'(10x,"charge from pdb residues: ",i0)') ichrg
  !--------------------------------------------------------------------
  ! SDF case
  case(fileType%sdf,fileType%molfile)
    ini = .false.
    topo%nb=0
    topo%nfrag=0
    do ibond = 1, len(mol%bonds)
      call mol%bonds%get_item(ibond,bond_ij)
      i = bond_ij(1)
      j = bond_ij(2)
      ni=topo%nb(20,i)
      ex=.false.
      do k=1,ni
        if(topo%nb(k,i).eq.j) then
          ex=.true.
          exit
        endif
      enddo
      if(.not.ex)then
        topo%nb(20,i)=topo%nb(20,i)+1
        topo%nb(topo%nb(20,i),i)=j
        topo%nb(20,j)=topo%nb(20,j)+1
        topo%nb(topo%nb(20,j),j)=i
      endif
    end do
    do i=1,mol%n
      if(topo%nb(20,i).eq.0)then
        dum1=1.d+42
        do j=1,i
          r=sqrt(sum((mol%xyz(:,i)-mol%xyz(:,j))**2))
          if(r.lt.dum1.and.r.gt.0.001)then
            dum1=r
            k=j
          endif
        enddo
        topo%nb(20,i)=1
        topo%nb(1,i)=k
      endif
    end do
  !--------------------------------------------------------------------
  ! General case: input = xyz or coord
  case default
    if (mol%npbc > 0) then
      call env%error("Input file format not suitable for GFN-FF!")
      return
    end if
    ini = .true.
    call open_file(ich,'.CHRG','r')
    if (ich.ne.-1) then
      read(ich,'(a)')atmp
      call close_file(ich)
      call readline(atmp,floats,s,ns,nf)
      topo%qfrag(1:nf)=floats(1:nf)
      ichrg=int(sum(topo%qfrag(1:nf)))
      topo%qfrag(nf+1:mol%n)=9999
    else
      topo%qfrag=0
    end if
  end select

  !-------------------------------------------------------------------

end subroutine gfnff_input

end module xtb_gfnff_setup