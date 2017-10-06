MODULE impurity_class

  !$$$$$$$$$$$$$$$$$$$$
  !$$ IMPURITY CLASS $$
  !$$$$$$$$$$$$$$$$$$$$

  use eigen_sector_class 

  use latticerout    , only : web,T1_T2_connect_unitcells
  use quantum_hamilt , only : Hamiltonian
  use matrix         , only : diag

  IMPLICIT NONE

  TYPE(masked_matrix_type), PUBLIC, SAVE :: Eccc

  REAL(DBL),  PARAMETER, PRIVATE         :: zero=0.0_DBL,one=1.0_DBL,two=2.0_DBL,three=3.0_DBL,four=4.0_DBL
  LOGICAL,    PARAMETER, PRIVATE         :: F=.FALSE.,T=.TRUE.


  TYPE impurity_type
    !$$$$$$$$$$$$$$$$$$$
    !$$ IMPURITY TYPE $$
    !$$$$$$$$$$$$$$$$$$$
    ! NUMBER OF SITES
    INTEGER :: Nc      = 0
    ! NUMBER OF 1-PARTICLE ORBITALS 
    INTEGER :: norbs   = 0
    ! SIZE OF REDUCED HILBERT SPACE OF THE IMPURITY
    INTEGER :: nstates = 0
    ! RANK OF ORBITALS
    INTEGER, POINTER :: iorb(:,:) => NULL()
    ! IMPURITY QUADRATIC ENERGY 
    TYPE(masked_matrix_type), POINTER :: Ec(:) => NULL()   ! in (site,site) basis for a given spin
    ! IMPURITY QUARTIC ENERGY 
    TYPE(masked_real_matrix_type) :: U  ! in (site,site) basis 
  END TYPE


CONTAINS

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE new_impurity(impurity,Nc,IMASKE,IMASKU) 
    TYPE(impurity_type), INTENT(INOUT) :: impurity
    INTEGER,             INTENT(IN)    :: Nc
    INTEGER, OPTIONAL,   INTENT(IN)    :: IMASKU(Nc,Nc),IMASKE(Nc,Nc,2)
    INTEGER                            :: spin

    CALL delete_impurity(impurity)

    ! NUMBER OF SITES
    impurity%Nc    = Nc

    ! NUMBER OF 1-PARTICLE ORBITALS
    impurity%norbs = Nc * 2
   
    ! NUMBER OF IMPURITY STATES
    impurity%nstates = 2**impurity%norbs
   
    ! ORDERING OF ORBITALS WITH INCREASING RANK  = |(site,up)> |(site,down)>

    IF(ASSOCIATED(impurity%iorb)) DEALLOCATE(impurity%iorb,STAT=istati) ; ALLOCATE(impurity%iorb(Nc,2)) 

    CALL ramp(impurity%iorb(:,1))

    impurity%iorb(:,2) = impurity%iorb(:,1) + Nc

    IF(PRESENT(IMASKE))THEN
      ! QUADRATIC ENERGY
      if(ASSOCIATED(impurity%Ec)) DEALLOCATE(impurity%Ec,STAT=istati) ; ALLOCATE(impurity%Ec(SIZE(IMASKE,3)))
      DO spin=1,SIZE(IMASKE,3)
       CALL new_masked_matrix(impurity%Ec(spin),"Ec(sz="//TRIM(cspin(spin))//")",Nc,Nc,IMASK=IMASKE(:,:,spin),IS_HERM=T)
      ENDDO
    ENDIF

    IF(PRESENT(IMASKU))THEN
      ! QUARTIC ENERGY
      CALL new_masked_real_matrix(impurity%U,"U",Nc,Nc,IMASK=IMASKU,IS_HERM=T)
    ENDIF

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE delete_impurity(IMP)
    TYPE(impurity_type), INTENT(INOUT) :: IMP
    INTEGER                            :: spin

    IF(ASSOCIATED(IMP%iorb)) DEALLOCATE(IMP%iorb,STAT=istati) 
    IF(ASSOCIATED(IMP%Ec))THEN
      DO spin=1,SIZE(IMP%Ec)
       CALL delete_masked_matrix(IMP%Ec(spin))
      ENDDO
     DEALLOCATE(IMP%Ec,STAT=istati)
    ENDIF

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE copy_impurity(IMPOUT,IMPIN)

    TYPE(impurity_type), INTENT(INOUT) :: IMPOUT
    TYPE(impurity_type), INTENT(IN)    :: IMPIN
    INTEGER                            :: spin

    IF(.NOT.ASSOCIATED(IMPIN%Ec))  STOP "ERROR IN copy_impurity: INPUT  ISNT ALLOCATED!"
    IF(.NOT.ASSOCIATED(IMPOUT%Ec)) STOP "ERROR IN copy_impurity: OUTPUT ISNT ALLOCATED!"
    IMPOUT%Nc      = IMPIN%Nc
    IMPOUT%norbs   = IMPIN%norbs
    IMPOUT%nstates = IMPIN%nstates
    DO spin=1,SIZE(IMPIN%Ec)
      CALL copy_masked_matrix(IMPOUT%Ec(spin),IMPIN%Ec(spin))
    ENDDO
    CALL copy_masked_real_matrix(IMPOUT%U,IMPIN%U)

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE define_impurity(impurity,mmu,impurity_,Himp,Eimp)
  
    !$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    !$$ READ IMPURITY PARAMETERS $$
    !$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

    TYPE(impurity_type), INTENT(INOUT) :: impurity
    type(web)                          :: impurity_
    type(hamiltonian)                  :: Himp
    integer                            :: jj,ff,k,i,j,kkk,ijk,ki,kj,kki,kkj,ii
    REAL(DBL)                          :: rval,mmu,val(impurity_%N**2)
    INTEGER                            :: mu,Nc,spin,iind_,iind
    INTEGER, ALLOCATABLE               :: IMASKU(:,:)

#ifdef _complex
    COMPLEX(DBL),OPTIONAL              :: Eimp(:,:)
#else
    REAL(DBL),OPTIONAL                 :: Eimp(:,:)
#endif

    CALL delete_impurity(impurity)
    Nc=impurity_%N

    write(log_unit,*) '......  starting impurity problem with number of site  :  ', Nc
    CALL new_impurity(impurity,Nc)

    !======================!
    ! NON-QUADRATIC ENERGY 
    !======================!

    if(allocated(IMASKU)) deallocate(IMASKU,STAT=istati); ALLOCATE(IMASKU(Nc,Nc))

    IMASKU = 0; kkk = 0 ; val = 0.d0
    
    do jj=1,Nc
      kkk           = kkk + 1
      IMASKU(jj,jj) = kkk
      if(.not.allocated(UUmatrix))then
        val(kkk)      = Himp%dU(impurity_%site(jj))
      else
        val(kkk)      = UUmatrix(jj,jj)
      endif
    enddo

    kkk=jj-1

    do jj=1,Nc
    if(.not.allocated(UUmatrix))then
     do i=1,impurity_%nneigh(impurity_%site(jj))
      if(impurity_%cadran(jj,i)==5)then
        kkk                               = kkk+1
        if(kkk>size(val)) then
         do j=1,Nc
         do ii=1,impurity_%nneigh(impurity_%site(j))
           if(impurity_%cadran(j,ii)==5)then
            write(log_unit,*) ' site, neighbor : ', j, impurity_%ineigh(j,ii)
           endif
         enddo
         enddo
         write(*,*) 'size val   : ', size(val)
         write(*,*) 'impurity%N : ', impurity_%N
         write(*,*) 'Nc         : ', Nc
         stop 'error build impurity Vrep matrix, too much elements, a geometry problem?'
        endif
        IMASKU(jj,impurity_%ineigh(jj,i)) = kkk
        val(kkk)                          = Himp%Vrep(impurity_%site(jj),i)
      endif
     enddo
    else
     do i=jj+1,Nc
       kkk=kkk+1
       if(kkk>size(val)) then
          write(*,*) 'stop error in building impurity'
          stop
       endif
       IMASKU(jj,i) = kkk
       val(kkk)     = UUmatrix(jj,i)
     enddo
    endif
    enddo
 
    CALL new_masked_real_matrix(impurity%U,"U",Nc,Nc,IMASK=IMASKU,IS_HERM=T)

    write(145+rank,*) '===== DIAGONALIZING IMP WITH ONSITE REPULSION ====='
    DO iind=1,impurity%U%MASK%nind
      rval=val(iind)
      CALL fill_masked_real_matrix(impurity%U,iind,rval)
    ENDDO
    call write_array(impurity%U%mat, ' Coulomb repulsion ', unit=145+rank, short=.true.)
    write(145+rank,*) '==================================================='


    ! TEST HERMITICITY
    write(log_unit,*) 'test hermiticity impurity U'
    CALL test_masked_real_matrix_symmetric(impurity%U)

    !======================!
    ! QUADRATIC ENERGY
    !======================!

    if(associated(impurity%Ec)) deallocate(impurity%Ec,STAT=istati); ALLOCATE(impurity%Ec(2))

    call update_impurity(impurity_%N,impurity,mmu,impurity_,Himp,Eimp=Eimp)

    if(allocated(IMASKU)) deallocate(IMASKU,STAT=istati)

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE update_impurity(Nc,impurity,mmu,impurity_,Himp,Eimp)
  
    TYPE(impurity_type), INTENT(INOUT) :: impurity
    type(web)                          :: impurity_
    type(hamiltonian)                  :: Himp
    integer                            :: jj,ff,k,i,j

#ifdef _complex
    COMPLEX(DBL)                       :: val(Nc**2*4)
    COMPLEX(DBL),OPTIONAL              :: Eimp(:,:)
#else
    REAL(DBL)                          :: val(Nc**2*4)
    REAL(DBL),OPTIONAL                 :: Eimp(:,:)
#endif

    REAL(DBL)                          :: rval,mmu
    INTEGER                            :: mu,Nc,spin,iind_,iind
    INTEGER                            :: IMASKE(Nc,Nc,2)

   IMASKE=0; k=0; val=0.d0 

   if(.not.present(Eimp))then

    do i=1,impurity_%N
     k=k+1
     if(allocated(Himp%eps)) val(k)=-mmu+Himp%eps(impurity_%site(i))
     IMASKE(i,i,1:2)=k
     if(allocated(impurity_%nneigh))then
     do j=1,impurity_%nneigh(impurity_%site(i))
      if(allocated(impurity_%ineigh).and.impurity_%cadran(i,j)==5)then
       k=k+1
       val(k)=Himp%teta(impurity_%site(i),j)
       IMASKE(i,impurity_%ineigh(i,j),1:2)=k
      endif
     enddo
     endif
    enddo

   else

    if(Nc/=impurity_%N)then
       write(*,*) 'something wrong in impurity class, size Nc'
       stop
    endif
    if(size(Eimp,1)/=2*impurity_%N)then
       write(*,*) 'something wrong in impurity class, size Eimp and Nc do not match'
       write(*,*) 'shape Eimp : ', shape(Eimp)
       write(*,*) 'impurity%N : ', impurity_%N 
      stop
    endif

    do i=1,impurity_%N
     do j=1,impurity_%N
      if(abs(Eimp(i,j))>1.d-7.or.i==j)then
       k=k+1
                val(k) =   Eimp(i,j)
       if(i==j) val(k) =   val(k) - mmu
       IMASKE(i,j,1)=k
      endif
      if(abs(Eimp(j+Nc,i+Nc))>1.d-7.or.i==j)then
       k=k+1
                val(k) = - Eimp(j+Nc,i+Nc)   !   Eimp in the supra form, here we want the TB form
       if(i==j) val(k) =   val(k) - mmu
       IMASKE(i,j,2)=k
      endif
     enddo
    enddo

   endif

    DO spin=1,2
      CALL new_masked_matrix(impurity%Ec(spin),"Ec(sz="//TRIM(cspin(spin))//")",Nc,Nc,IMASK=IMASKE(:,:,spin),IS_HERM=T)
    ENDDO
    CALL clean_redundant_imask(impurity%Ec)

    DO spin=1,SIZE(impurity%Ec)
      do i=1,k
       CALL fill_masked_matrix(impurity%Ec(spin),i,val(i)) 
      enddo
      call write_array( impurity%Ec(spin)%rc%mat , ' Ec(spin) ' , unit=log_unit, short=.true. )
      call write_array( IMASKE(:,:,spin), ' mask spin ', unit=log_unit )
    enddo

    if(present(Eimp))then
      call write_array( Eimp, ' real Eimp ' , unit=log_unit, short=.true.)
    endif

    ! TEST HERMITICITY
    DO spin=1,SIZE(impurity%Ec)
      write(log_unit,*) 'test hermiticity Ec spin ', spin
      CALL test_masked_matrix_hermitic(impurity%Ec(spin))
    ENDDO

    CALL delete_masked_matrix(Eccc)
    CALL Nambu_Ec(Eccc,impurity%Ec)

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE write_impurity(impurity,UNIT)

    TYPE(impurity_type), INTENT(IN) :: impurity
    INTEGER, OPTIONAL,   INTENT(IN) :: UNIT
    INTEGER                         :: unit_,spin

    IF(.NOT.ASSOCIATED(impurity%U%mat)) STOP "ERROR IN write_impurity: INPUT  ISNT ALLOCATED!"

    CALL dump_message(UNIT=UNIT,TEXT="################")
    CALL dump_message(UNIT=UNIT,TEXT="### IMPURITY ###")
    CALL dump_message(UNIT=UNIT,TEXT="################")

                      unit_ = log_unit 
    IF(PRESENT(UNIT)) unit_ = UNIT

    WRITE(unit_,'(a,I0)') "# Nb of sites in the impurity : Nc = ",impurity%Nc

    DO spin=1,SIZE(impurity%Ec)
      write(unit_,*) ' =================================== '
      CALL write_masked_matrix(impurity%Ec(spin),UNIT=UNIT,SHORT=T)
    ENDDO

    write(unit_,*) ' =================================== '
    CALL write_masked_real_matrix(impurity%U,UNIT=UNIT,SHORT=T)

  END SUBROUTINE 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE Nambu_Ec(EcNambu,Ec)

    ! EMBED IMPURITY QUADRATIC ENERGY IN NAMBU MATRICES 

    TYPE(masked_matrix_type), INTENT(INOUT) :: EcNambu
    TYPE(masked_matrix_type), INTENT(IN)    :: Ec(:)
    INTEGER                                 :: Nc ! for clarity only

    IF(SIZE(Ec)==0) STOP "ERROR IN Nambu_Ec: INPUT Ec ISNT ALLOCATED!"

    Nc = Ec(1)%rc%n1
    CALL new_masked_matrix(EcNambu,"EcNambu",Nc*2,Nc*2,IS_HERM=T)

    ! UPPER LEFT BLOCK (SPIN UP)
    EcNambu%rc%mat(   1:Nc,     1:Nc)   =             Ec(1)%rc%mat

    ! LOWER RIGHT BLOCK (SPIN DOWN)
    EcNambu%rc%mat(Nc+1:Nc*2,Nc+1:Nc*2) = - TRANSPOSE(Ec(2)%rc%mat)

    energy_global_shift =  sum(diag( Ec(2)%rc%mat ))

  END SUBROUTINE

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  FUNCTION average_chem_pot(impurity) 
  TYPE(impurity_type), INTENT(IN) :: impurity
  REAL(DBL)                       :: average_chem_pot
  INTEGER                         :: spin,nspin
  LOGICAL                         :: is_diag(impurity%Nc,impurity%Nc)

    CALL new_diag(is_diag,impurity%Nc)

    ! COMPUTE AVERAGE CHEMICAL POTENTIAL
    nspin = SIZE(impurity%Ec)

    DO spin=1,nspin
     average_chem_pot = average_chem_pot + SUM(impurity%Ec(spin)%rc%mat,is_diag)
    ENDDO
    average_chem_pot = average_chem_pot / ( nspin * impurity%Nc ) 

  END FUNCTION 

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

  SUBROUTINE shift_average_chem_pot(new_chem_pot,impurity) 
    TYPE(impurity_type)                :: impurity
    REAL(DBL),           INTENT(IN)    :: new_chem_pot
    REAL(DBL)                          :: mean_chem_pot
    INTEGER                            :: spin,nspin
    LOGICAL                            :: is_diag(impurity%Nc,impurity%Nc)

    CALL new_diag(is_diag,impurity%Nc)

    ! SHIFT AVERAGE CHEMICAL POTENTIAL TO new_chem_pot
    nspin = SIZE(impurity%Ec)

    ! COMPUTE OLD AVERAGE CHEMICAL POTENTIAL
    mean_chem_pot = average_chem_pot(impurity)

    DO spin=1,nspin
      WHERE(is_diag)
       impurity%Ec(spin)%rc%mat = impurity%Ec(spin)%rc%mat + new_chem_pot - mean_chem_pot
      END WHERE
    ENDDO

  END SUBROUTINE

!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************
!**************************************************************************

END MODULE 