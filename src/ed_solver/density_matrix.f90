MODULE density_matrix

   implicit none

   private

   !----------------------------------------------------!
   ! COMPUTE THE REDUCED DENSITY MATRIX OF THE IMPURITY !
   !----------------------------------------------------!

   public :: analyze_density_matrix
   public :: compute_density_matrix

contains

   subroutine compute_density_matrix(dmat, AIM, beta, GS)

      ! COMPUTE THE REDUCED DENSITY MATRIX OF THE IMPURITY

      use eigen_sector_class, only: eigensector_type, eigensectorlist_type, &
         gsenergy, partition
      use genvar, only: dp, iproc, no_mpi, nproc, size2
      use linalg, only: conj, dexpc
      use common_def, only: dump_message, reset_timer, timer_fortran
      use sector_class, only: is_in_sector, rank_func
      use aim_class, only: aim_type, impbath2aimstate
      use mpi_mod, only: split
      use rcmatrix_class, only: rcmatrix_type
      use eigen_class, only: eigen_type
      use timer_mod, only: start_timer, stop_timer

      implicit none

      TYPE(rcmatrix_type), INTENT(INOUT)     :: dmat
      TYPE(AIM_type), INTENT(IN)             :: AIM
      REAL(DP), INTENT(IN)                  :: beta
      TYPE(eigensectorlist_type), INTENT(IN) :: GS ! list of lowest eigenstates
      REAL(DP)                       :: boltz, Zpart, E0
      INTEGER                         :: AIMrank1, AIMrank2, IMPrank1, &
                                         IMPrank2, BATHrank
      INTEGER                         :: AIMstate1, AIMstate2
      INTEGER                         :: nIMPstates, nBATHstates, Nb, Nc
      INTEGER                         :: start_compute
      INTEGER                         :: IMPchunk(nproc), IMPstatemin(nproc), &
                                         IMPstatemax(nproc)
#ifdef _complex
      COMPLEX(DP)                    :: coeff1, coeff2
      COMPLEX(DP), ALLOCATABLE       :: dmat_vec(:), dmat_vec_tot(:)
#else
      REAL(DP)                       :: coeff1, coeff2
      REAL(DP), ALLOCATABLE          :: dmat_vec(:), dmat_vec_tot(:)
#endif
      INTEGER, ALLOCATABLE            :: rankmin(:), rankmax(:), rankchunk(:)
      INTEGER                         :: thisrank, isector, ieigen
      TYPE(eigensector_type), POINTER :: es => NULL()
      TYPE(eigen_type), POINTER       :: eigen => NULL()

      call start_timer("compute_density_matrix")

      CALL dump_message(TEXT="# START COMPUTING THE REDUCED DENSITY &
           &MATRIX... ")
      CALL reset_timer(start_compute)

      nIMPstates = AIM%impurity%nstates
      Nc = AIM%impurity%Nc
      nBATHstates = AIM%bath%nstates
      Nb = AIM%bath%Nb

      CALL split(nIMPstates, IMPstatemin, IMPstatemax, IMPchunk)

      Zpart = partition(beta, GS)
      E0 = GSenergy(GS)
      dmat%rc = 0.0_DP

      DO isector = 1, GS%nsector

         es => GS%es(isector)

         !----------------------------------------------!
         ! PARSE THE LIST OF EIGENSTATES IN THIS SECTOR !
         !----------------------------------------------!

         DO ieigen = 1, es%lowest%neigen

            eigen => es%lowest%eigen(ieigen)

            boltz = DEXPc(-beta*(eigen%val - E0)) ! Boltzman factor

            !----------------------------------------------!
            ! LOOP OVER MATRIX ELEMENTS WE WANT TO COMPUTE !
            !----------------------------------------------!

!$OMP             PARALLEL PRIVATE(IMPrank1, IMPrank2, BATHrank, AIMstate1, &
!$OMP                  AIMrank1, AIMstate2, AIMrank2, coeff1, coeff2)
!$OMP             DO
            DO IMPrank1 = IMPstatemin(iproc), IMPstatemax(iproc)
               DO IMPrank2 = 1, IMPrank1

                  !---------------------------------------!
                  ! TRACE OUT THE BATH DEGREES OF FREEDOM !
                  !---------------------------------------!

                  DO BATHrank = 1, nBATHstates
                     CALL IMPBATH2AIMstate(AIMstate1, IMPrank1 - 1, BATHrank - 1, &
                                           Nc, Nb)
                     IF (is_in_sector(AIMstate1, es%sector)) THEN
                        AIMrank1 = rank_func(AIMstate1, es%sector)
                        coeff1 = eigen%vec%rc(AIMrank1)
                        IF (coeff1 /= 0.0_DP) THEN
                           CALL IMPBATH2AIMstate(AIMstate2, IMPrank2 - 1, &
                                                 BATHrank - 1, Nc, Nb)
                           IF (is_in_sector(AIMstate2, es%sector)) THEN
                              AIMrank2 = rank_func(AIMstate2, es%sector)
                              coeff2 = eigen%vec%rc(AIMrank2)
                              IF (coeff2 /= 0.0_DP) THEN
                                 dmat%rc(IMPrank1, IMPrank2) = &
                                    dmat%rc(IMPrank1, IMPrank2) + coeff1* &
                                    conj(coeff2)*boltz
                                 IF (IMPrank1 /= IMPrank2) dmat%rc(IMPrank2, &
                                                                   IMPrank1) = dmat%rc(IMPrank2, IMPrank1) &
                                             + conj(coeff1)*coeff2*boltz
                              ENDIF
                           ENDIF
                        ENDIF
                     ENDIF
                  ENDDO ! end loop over bath states

               ENDDO
            ENDDO ! loop over impurity states
!$OMP             END DO
!$OMP             END PARALLEL
         ENDDO ! loop over eigenstates

      ENDDO ! loop over eigensectors

      write (*, *) '............ end main loops density matrix ............'

      if (size2 > 1 .and. .not. no_mpi) call mpi_collect_

      ! RENORMALIZE USING PARTITION FUNCTION
      ! 1 if T = 0, 1 also at T > 0 if we had all the eigenstates

      dmat%rc = dmat%rc/Zpart

      CALL timer_fortran(start_compute, "# ... TOOK ")

      call stop_timer("compute_density_matrix")

   contains

      subroutine mpi_collect_()

         use genvar, only: ierr, iproc, nproc, size2
         use mpi

         implicit none

         write (*, *) 'start collecting MPI chunks'

         ALLOCATE (rankmin(nproc), rankmax(nproc), rankchunk(nproc))
         rankmin = IMPstatemin*(IMPstatemin - 1)/2 + 1
         rankmax = IMPstatemax*(IMPstatemax + 1)/2
         rankchunk = rankmax - rankmin + 1

         ALLOCATE (dmat_vec(rankchunk(iproc)), dmat_vec_tot(rankmax(nproc)))

         DO IMPrank1 = IMPstatemin(iproc), IMPstatemax(iproc)
            thisrank = IMPrank1*(IMPrank1 - 1)/2
            DO IMPrank2 = 1, IMPrank1
               dmat_vec_tot(thisrank + IMPrank2) = dmat%rc(IMPrank1, IMPrank2)
               dmat_vec(thisrank + IMPrank2 - rankmin(iproc) + 1) = &
                  dmat%rc(IMPrank1, IMPrank2)
            ENDDO
         ENDDO

         write (*, *) 'COLLECTING DATA IN DENSITY MATRIX'

         if (size2 > 1 .and. .not. no_mpi) then
#ifdef _complex
            CALL MPI_ALLGATHERV(dmat_vec, rankchunk(iproc), MPI_DOUBLE_COMPLEX, &
                                dmat_vec_tot, rankchunk, rankmin - 1, MPI_DOUBLE_COMPLEX, &
                                MPI_COMM_WORLD, ierr)
#else
            CALL MPI_ALLGATHERV(dmat_vec, rankchunk(iproc), &
                                MPI_DOUBLE_PRECISION, dmat_vec_tot, rankchunk, rankmin - 1, &
                                MPI_DOUBLE_PRECISION, MPI_COMM_WORLD, ierr)
#endif
         endif

         IF (ierr /= 0 .and. size2 > 1 .and. .not. no_mpi) CALL &
            MPI_ABORT(MPI_COMM_WORLD, 1, ierr)

         DO IMPrank1 = 1, nIMPstates
            IF (IMPrank1 < IMPstatemin(iproc) .OR. IMPrank1 > &
                IMPstatemax(iproc)) THEN
               thisrank = IMPrank1*(IMPrank1 - 1)/2
               dmat%rc(IMPrank1, IMPrank1) = dmat_vec_tot(thisrank + IMPrank1)
               DO IMPrank2 = 1, IMPrank1 - 1
                  dmat%rc(IMPrank1, IMPrank2) = dmat_vec_tot(thisrank + IMPrank2)
                  dmat%rc(IMPrank2, IMPrank1) = conj(dmat%rc(IMPrank1, IMPrank2))
               ENDDO
            ENDIF
         ENDDO

         if (allocated(dmat_vec)) deallocate (dmat_vec)
         if (allocated(dmat_vec_tot)) deallocate (dmat_vec_tot)
         if (allocated(rankmin)) deallocate (rankmin)
         if (allocated(rankmax)) deallocate (rankmax)
         if (allocated(rankchunk)) deallocate (rankchunk)

      end subroutine

   end subroutine

   subroutine analyze_density_matrix(dmat, IMPiorb, NAMBU)

      ! COMPUTE & DISPLAY THE FIRST EIGENPAIRS OF THE DENSITY MATRIX
      ! COMPUTE THE ENTANGLEMENT ENTROPY:
      ! S = - SUM_i ( lambda_i * log(lambda_i) )
      ! WHERE lambda_i ARE THE EIGENVALUES OF THE DENSITY MATRIX

      use genvar, only: dp, log_unit
      use globalvar_ed_solver, only: ed_num_eigenstates_print
      use common_def, only: c2s, dump_message, i2c
      use matrix, only: diagonalize, write_array
      use readable_vec_class, only: cket_from_state
      use sorting, only: qsort_array, qsort_adj_array

      implicit none

      INTEGER, INTENT(IN)      :: IMPiorb(:, :)
      LOGICAL, INTENT(IN)      :: NAMBU
#ifdef _complex
      COMPLEX(DP), INTENT(IN) :: dmat(:, :)
      COMPLEX(DP)             :: VECP(SIZE(dmat, 1), SIZE(dmat, 1))
#else
      REAL(DP), INTENT(IN)    :: dmat(:, :)
      REAL(DP)                :: VECP(SIZE(dmat, 1), SIZE(dmat, 1))
#endif
      REAL(DP)             :: VALP(SIZE(dmat, 1)), absvec(SIZE(dmat, 1))
      INTEGER               :: states(size(dmat, 1))
      REAL(DP)             :: ENTROPY, TRACE
      INTEGER               :: ivp, nvp, icomp
      CHARACTER(LEN=:), allocatable :: cvec
      character(1000)       :: prefix
      INTEGER               :: npairs, ncomp, ncompi
      character(100)        :: intwri

#ifdef DEBUG
      write (*, *) "DEBUG: entering density_matrix_analyze_density_matrix"
#endif

      ! NUMBER OF EIGENVALUES TO DISPLAY, NUMBER OF EIGENVECTOR COMPONENTS TO
      ! DISPLAY

      ncomp = min(size(dmat, 1), ed_num_eigenstates_print)
      npairs = ncomp

      if (size(dmat, 1) <= ed_num_eigenstates_print) then
         call write_array(dmat, " DENSITY MATRIX ", unit=log_unit, short=.true.)
      end if

      write (*, *) 'analyse density matrix'

      nvp = SIZE(dmat, 1)
      CALL diagonalize(dmat, VALP, VECP, EIGENVAL_ONLY=.false.)
      CALL dump_message(TEXT="# "//c2s(i2c(npairs))//" LARGEST &
           &EIGENVALUES OF THE DENSITY MATRIX:")

      DO ivp = nvp, nvp - (npairs - 1), -1 ! loop over the npairs largest
         ! eigenvalues
         absvec = ABS(VECP(:, ivp))
         states = (/(icomp, icomp=1, nvp)/)

         ! Sort components of eigenvector in decreasing order

         ! First sort absvec in ascending order
         call qsort_array(absvec, states)

         ! Flip to decreasing order
         absvec = absvec(nvp:1:-1)
         states = states(nvp:1:-1)

         ncompi = ncomp
         do icomp = ncomp, 1, -1
            if (abs(VECP(states(icomp), ivp)) > 1.d-10) then
               ncompi = icomp
               exit
            endif
         enddo

         write (log_unit, *) '======================================================='
#ifdef _complex
         intwri = '('//c2s(i2c(ncompi))//'(2f9.6, a))'
         allocate(character(len=ncompi*19) :: cvec)
         write (log_unit, *) 'non zero elements in state vector  : ', ncompi
         write (log_unit, *) (VECP(states(icomp), ivp), " "// &
                              cket_from_state(states(icomp) - 1, IMPiorb, NAMBU)//" ", &
                              icomp=1, ncompi)
         WRITE (cvec, ADJUSTL(TRIM(intwri))) (real(VECP(states(icomp), &
                                                        ivp)), aimag(VECP(states(icomp), ivp)), " "// &
                                              cket_from_state(states(icomp) - 1, IMPiorb, NAMBU)//" ", &
                                              icomp=1, ncompi)
#else
         intwri = '('//c2s(i2c(ncompi))//'(f9.6, a))'
         allocate(character(len=ncompi*10) :: cvec)
         write (log_unit, *) 'non zero elements in state vector  : ', ncompi
         write (log_unit, *) (VECP(states(icomp), ivp), " "// &
                              cket_from_state(states(icomp) - 1, IMPiorb, NAMBU)//" ", &
                              icomp=1, ncompi)
         WRITE (cvec, ADJUSTL(TRIM(intwri))) (VECP(states(icomp), ivp), " &
              &"//cket_from_state(states(icomp) - 1, IMPiorb, NAMBU)//" &
              &", icomp=1, ncompi)
#endif
         write (log_unit, *) &
            '-------------------------------------------------------'
         prefix = "# "//c2s(i2c(nvp - ivp + 1))//"   "
         WRITE (log_unit, '(a'//c2s(i2c(LEN_TRIM(prefix)))//', f9.6, a)') &
            TRIM(prefix), VALP(ivp), " - > "//TRIM(cvec)
         deallocate(cvec)
         write (log_unit, *) '======================================================='

      ENDDO

      write (*, *) '.... start entropy ....'

      write (log_unit, *) '-----------------------------------------'
      write (log_unit, *) 'EIGENVALUES ARE : '
      write (log_unit, '(1000f6.3)') VALP
      write (log_unit, *) '-----------------------------------------'

      ENTROPY = 0.0_DP
      TRACE = 0.0_DP
      DO ivp = nvp, 1, -1
         IF (VALP(ivp) > 1.d-16) ENTROPY = ENTROPY - VALP(ivp)*LOG(VALP(ivp))
         TRACE = TRACE + VALP(ivp)
      ENDDO
      write (*, *) '.... done ....'
      WRITE (log_unit, '(a, f9.6)') "# CHECK TRACE          = ", TRACE
      WRITE (log_unit, '(a, f9.6)') "# ENTANGLEMENT ENTROPY = ", ENTROPY
      CALL flush(log_unit)

#ifdef DEBUG
      write (*, *) "DEBUG: leaving density_matrix_analyze_density_matrix"
#endif

   end subroutine

end module
