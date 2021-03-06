module ed_arpack

   use genvar, only: DP

   implicit none

   private

   !-------------------------------!
   ! DIAGONALIZATION FULL SPETRUM  !
   !-------------------------------!

   public :: arpack_diago, ed_diago

contains

   subroutine ARPACK_diago(lowest)

      use common_def, only: reset_timer, timer_fortran
      use eigen_class, only: add_eigen, eigenlist_type, &
         is_eigen_in_window
      use genvar, only: rank
      use globalvar_ed_solver, only: dEmax, neigen, tolerance
      use H_class, only: dimen_H, hmultc, hmultr, title_h_

      implicit none

      TYPE(eigenlist_type), INTENT(INOUT) :: lowest
#ifdef _complex
      COMPLEX(DP), ALLOCATABLE :: VECP(:, :)
#else
      REAL(DP), ALLOCATABLE    :: VECP(:, :)
#endif
      REAL(DP), ALLOCATABLE    :: VALP(:)
      INTEGER                   :: start_diagH
      REAL(DP)                 :: a
      INTEGER                   :: jj, ii, i, j
      REAL(DP)                 :: coeff
      INTEGER                   :: dimenvec, Neigen_, nconv

      CALL reset_timer(start_diagH)
      if (dimen_H() == 0) stop 'error Hilbert space has 0 dimension'
      dimenvec = dimen_H()

#ifdef _complex
      Neigen_ = min(dimen_H() - 1, Neigen)
#else
      Neigen_ = min(dimen_H() - 1, 2*Neigen)
#endif

      ALLOCATE (VECP(dimen_H(), Neigen_), VALP(Neigen_))

      if (Neigen_ > 0) then
         write (*, *) '======= RUNNING ARPACK WITH NEIGEN = ', Neigen_, '========'
#ifdef _arpack
#ifdef _complex
         call arpack_eigenvector_sym_matrix_(.true., 'SR', tolerance, &
                                             dimenvec, .true., VALP(1:Neigen_), VECP(1:dimenvec, 1:Neigen_), &
                                             Neigen_, nconv, av=Hmultc)
#else
         call arpack_eigenvector_sym_matrix(.true., 'BE', tolerance, &
                                            dimenvec, .true., VALP(1:Neigen_), VECP(1:dimenvec, 1:Neigen_), &
                                            Neigen_, nconv, av=Hmultr)
#endif
#else
         write (*, *) 'error ARPACK library not present, recompile with &
              &-D_arpack'
         stop
#endif

#ifndef _complex
         if (mod(nconv, 2) == 0) then
            nconv = nconv/2
         else
            if (nconv /= 1) then
               nconv = (nconv + 1)/2
            endif
         endif
#endif

         j = 1
         do i = 2, nconv
            if (.not. is_eigen_in_window(VALP(i), [VALP(1), VALP(1) + dEmax])) then
               j = i
               exit
            endif
         enddo
         nconv = j

         write (*, *) 'ARPACK converged --- > : ', nconv
         CALL timer_fortran(start_diagH, "# BUILDING OF "// &
                            TRIM(ADJUSTL(title_H_()))//" TOOK ")
         if (nconv > 0) then
            CALL reset_timer(start_diagH)
            CALL add_eigen(nconv, VECP, VALP, lowest)
            CALL timer_fortran(start_diagH, "# STORING "// &
                               TRIM(ADJUSTL(title_H_()))//" TOOK ")
            if (rank == 0) then
               write (*, *) '====================================================='
               write (*, *) ' GETTING THE GROUND STATE '
               write (*, *) '  N eigenvalues    : ', lowest%neigen
               write (*, *) '  eigenvalues      : ', lowest%eigen(:)%val
               write (*, *) '  SECTOR dimension : ', lowest%eigen(1)%dim_space
               write (*, *) '====================================================='
            endif
         endif
      else
         nconv = 0
      endif

      IF (ALLOCATED(VALP)) DEALLOCATE (VALP)
      IF (ALLOCATED(VECP)) DEALLOCATE (VECP)

      return
   end subroutine

   subroutine ED_diago(lowest)

      use rcvector_class, only: delete_rcvector, new_rcvector, rcvector_type
      use common_def, only: reset_timer, timer_fortran, utils_assert
      use eigen_class, only: add_eigen, eigenlist_type, &
         is_eigen_in_window
      use genvar, only: rank
      use h_class, only: dimen_H, hmult__, title_h_
      use matrix, only: eigenvector_matrix
      use globalvar_ed_solver, only: dEmax, FLAG_FULL_ED_GREEN
      use timer_mod, only: start_timer, stop_timer

      implicit none

      TYPE(eigenlist_type), INTENT(INOUT) :: lowest
#ifdef _complex
      COMPLEX(DP), ALLOCATABLE :: VECP(:, :)
#else
      REAL(DP), ALLOCATABLE    :: VECP(:, :)
#endif
      REAL(DP), ALLOCATABLE    :: VALP(:)
      TYPE(rcvector_type)       :: invec, outvec
      INTEGER                   :: start_diagH
      REAL(DP)                 :: a
      INTEGER                   :: jj, ii, i, j
      REAL(DP)                 :: coeff
      INTEGER                   :: dimenvec

      CALL reset_timer(start_diagH)
      ALLOCATE (VECP(dimen_H(), dimen_H()), VALP(dimen_H()))

      call utils_assert(dimen_H() > 0, "Error in ed_arpack: Hilbert space has 0 dimension")

      dimenvec = dimen_H()
      CALL new_rcvector(invec, dimenvec)
      CALL new_rcvector(outvec, dimenvec)

      invec%rc = 0.d0

      DO ii = 1, dimenvec
         ! H |v_i > to build H_ij !
         invec%rc(ii) = 1.d0
         CALL Hmult__(dimenvec, outvec%rc, invec%rc)
         VECP(:, ii) = outvec%rc
         invec%rc(ii) = 0.d0
      ENDDO

      ! CALL timer_fortran(start_diagH, "# BUILDING OF "// &
      !                    TRIM(ADJUSTL(title_H_()))//" TOOK ")
      ! CALL reset_timer(start_diagH)
      call start_timer("ed_diago_mp_eigenvector_matrix")
      call eigenvector_matrix(lsize=dimenvec, mat=VECP, vaps=VALP, &
                              eigenvec=VECP)
      call stop_timer("ed_diago_mp_eigenvector_matrix")
      ! CALL timer_fortran(start_diagH, "# DIAGONALIZATION OF "// &
      !                    TRIM(ADJUSTL(title_H_()))//" TOOK ")
      ! CALL reset_timer(start_diagH)

      if (.not. FLAG_FULL_ED_GREEN) then
         j = 1
         do i = 2, size(VALP)
            write (*, *) 'diff val, dEmax : ', VALP(i) - VALP(1), dEmax, &
               is_eigen_in_window(VALP(i), [VALP(1), VALP(1) + dEmax])
            if (.not. is_eigen_in_window(VALP(i), [VALP(1), VALP(1) + dEmax])) then
               j = i
               exit
            endif
         enddo
      else
         j = dimenvec
      endif

      CALL add_eigen(j, VECP, VALP, lowest)

      IF (ALLOCATED(VALP)) DEALLOCATE (VALP)
      IF (ALLOCATED(VECP)) DEALLOCATE (VECP)

      CALL delete_rcvector(invec)
      CALL delete_rcvector(outvec)
      CALL timer_fortran(start_diagH, "# STORING "// &
                         TRIM(ADJUSTL(title_H_()))//" TOOK ")

      if (rank == 0) then
         write (*, *) '====================================================='
         write (*, *) '  GETTING THE GROUD STATE                            '
         write (*, *) '  N eigenvalues    : ', lowest%neigen
         write (*, *) '  dEmax            : ', dEmax
         write (*, *) '  j                : ', j
         write (*, *) '  eigenvalues      : ', lowest%eigen(:)%val
         write (*, *) '  SECTOR dimension : ', lowest%eigen(1)%dim_space
         write (*, *) '====================================================='
      endif

      return
   end subroutine

end module
