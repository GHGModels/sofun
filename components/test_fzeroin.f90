! ----------------------- MODULE fzeroin.f90 ---------------------------
module fzeroin
  !************************************************************************
  !*                                                                      *
  !* Compute a zero of a continuous real valued function with the         *
  !* ------------------------------------------------------------         *
  !* Zeroin method.                                                       *
  !* --------------                                                       *
  !*                                                                      *
  !* exported funktion:                                                   *
  !*   - zeroin():  Zeroin- method for real functions                     *
  !*                                                                      *
  !* Programming language: ANSI C                                         *
  !* Compiler:             Borland C++ 2.0                                *
  !* Computer:             IBM PS/2 70 mit 80387                          *
  !* Author:               Siegmar Neuner                                 *
  !* Modifications:        Juergen Dietel, Rechenzentrum, RWTH Aachen     *
  !* Source:               FORTRAN source code                            *
  !* Date:                 11. 27. 1992                                   *
  !* -------------------------------------------------------------------- *
  !* Ref.: "Numerical Algorithms with C By G. Engeln-Mueller and F. Uhlig,*
  !*        Springer-Verlag, 1996" [BIBLI 11].                            *
  !*                                                                      *
  !*                                 F90 version by J-P Moreau, Paris.    *
  !*                                        (www.jpmoreau.fr)             *
  !************************************************************************

  parameter(FOUR=4.d0,HALF=0.5d0,ONE=1.d0,THREE=3.d0,TWO=2.d0)
  parameter(ZERO=0.d0, XMACHEPS = 1.2d-16)   !machine smallest real number

  type outtype_zeroin
    real*8 :: root
    real*8 :: froot
    integer :: niter
    integer :: error
  end type outtype_zeroin

contains

  ! !test function F(x)
  ! subroutine Fkt(x,y)
  !   real*8 x,y
  !   y = 5.d0*x - dexp(x)
  !   return
  ! end subroutine

  function Fkt( x ) result ( y )
    real*8, intent(in) :: x
    real*8, intent(out) :: y
    y = 5.d0*x - dexp(x)
  end function Fkt

  ! subroutine zeroin  &             ! Find roots with the Zeroin method
  !           (        &
  !            myabserr, &             ! absolute error bound ..............
  !            myrelerr, &             ! relative error bound ..............
  !            fmax,   &             ! maximal number of calls for fkt() .
  !            protnam, &            ! Name of the log file ..............
  !            x1,      &             ! [a,b] = inclusion interval ........
  !            x2,      &             ! right endpoint or zero ............
  !            b,      &             ! root
  !            fb,     &             ! Function value at the root b ......
  !            fanz,   &             ! number of actual function calls ...
  !            rc      &             ! error code ........................
  !           )

  function zeroin( myabserr, myrelerr, fmax, x1, x2, protnam ) result( b )
    
    real*8, intent(in)    :: myabserr, myrelerr
    integer, intent(in)   :: fmax
    real*8, intent(in)    :: x1
    real*8, intent(in)    :: x2
    character(len=*), intent(in), optional :: protnam

    real*8, intent(out)   :: b

    type(outtype_zeroin) :: out_zeroin

    ! real*8  abserr,relerr,a,b,fb
    ! integer fmax,fanz,rc
    ! character*(*) protnam
    !************************************************************************
    !* Given a real valued function f on an interval [a,b] with             *
    !* f(a) * f(b) < 0, we compute a root of f in [a,b].                    *
    !* The Zeroin method combines bisection and secant methods with inverse *
    !* quadratic interpolation.                                             *
    !*                                                                      *
    !* Input parameters:                                                    *
    !* =================                                                    *
    !* abserr\  Error bounds with   abserr >= 0  and  relerr >= 0. Their    *
    !* relerr/  sum must exceed zero. For break-off we use the test         *
    !*              |xm|  <=  0.5 * (abserr + |b| * relerr),                *
    !*          where xm denotes half the length of the final inclusion     *
    !*          interval. For relerr = 0 we test only for absolute error,   *
    !*          while for  abserr = 0, we test the relative error only.     *
    !*          abserr and relerr are used as put in only when both exceed  *
    !*          four times the machine constant. Otherwise we set them to   *
    !*          this value.                                                 *
    !* fmax     upper limit of calls of function                            *
    !* protnam  Name of a file used for intermediate results. If the pointer*
    !*          is set to zero, we do not use this file.                    *
    !* a,b      end points of the interval, that includes a root            *
    !*                                                                      *
    !* Output parameters:                                                   *
    !* =================                                                    *
    !* abserr\  actual error bounds used                                    *
    !* relerr/                                                              *
    !* b        approximate root                                            *
    !* fb       value of f at the root b                                    *
    !* fanz     number of calls of  fkt()                                   *
    !*                                                                      *
    !* Error code rc:                                                       *
    !* =============                                                        *
    !* = -2: abserr or relerr is negative, or both are zero, or fmax < 1.   *
    !* = -1: The necessary assumption  f(a) * f(b) < 0  is violated.        *
    !* =  0: Desired accuracy has been reache :                             *
    !*           |xm|  <=  0.5 * (abserr + |b| * relerr).                   *
    !* =  1: b on output is a root with  fkt(b) = 0.                        *
    !* =  2: Either a or b is a root at input.                              *
    !* =  3: After fmax calls of Fkt the algorithm has not found a root     *
    !* =  4: Error when opening intermediate result file                    *
    !*                                                                      *
    !************************************************************************
    !Label: 50
    real*8 fa,      &          ! Function value fkt(a)                    
           fc,      &          ! Function value fkt(c)                    
           eps,     &          ! minimal value for error bounds abserr and relerr
           tol1,    &          ! auxiliary variable for mixed error bound 
           xm,      &          ! half of the current interval length      
           c,       &          ! value inside [a,b]                       
           d,       &          ! Distance to the nearest approximate root 
           e,       &          ! previous value of d                      
           p,       &
           q,       &
           r,       &
           s,       &
           tmp                 ! auxiliary variable to check inclusion    
                               !   f(a) * f(b) < 0                        
    integer fehler             ! error code of this function              

    real*8 :: abserr, relerr
    real*8 :: a

    real*8   :: fb
    integer  :: fanz
    integer  :: rc

    ! ------------------ initialize variables -----------------------------
      a = x1
      b = x2

      abserr = myabserr
      relerr = myrelerr

      c=ZERO; d=ZERO; e=ZERO; rc=0; fehler=0
      eps = FOUR * XMACHEPS

      fa = Fkt(a)
      fb = Fkt(b)

      fanz = 2

    ! ----------- check   f(a) * f(b) < 0  --------------------------------
      tmp = fa * fb
      if (tmp > ZERO) then
        rc = -1
      else if (tmp == ZERO) then
        rc = 2
      end if
      if (rc.ne.0)  return

    ! ----------- check usability of given error bounds -------------------
      if (abserr < ZERO.or.relerr < ZERO.or.abserr + relerr <= ZERO.or.fmax < 1) then
        rc = -2
        return
      end if

      if (relerr==ZERO.and.abserr < eps) then
        abserr = eps
      else if (abserr==ZERO.and.relerr < eps) then
        relerr = eps
      else
        if (abserr < eps)  abserr = eps
        if (relerr < eps)  relerr = eps
      end if

      if (present(protnam)) then
        open(unit=2,file='tzeroin.log',status='unknown')  
      else
        rc = 4
        return
      end if

      fc=fb
      do while (2>1)                          ! start iteration

        if (fb * (fc / DABS(fc)) > ZERO) then ! no inclusion of a root
          c  = a                              ! between b and c ?
          fc = fa                             ! alter c so that b and c
          e  = b - a                          ! include the root of f
          d  = e
        end if

        if (DABS(fc) < DABS(fb)) then         ! If fc has the smaller modulus
          a   = b                             ! interchange interval end
          b   = c                             ! points
          c   = a
          fa  = fb
          fb  = fc
          fc  = fa
        end if

        write(2,100)  a, b, c
        write(2,110)  fa, fb, fc

        tol1 = HALF * (abserr + relerr * DABS(b));
        xm   = HALF * (c - b);

        write(2,120)  xm, tol1

        if (DABS(xm) <= tol1) then       ! reached desired accuracy ?
          fehler = 0
          return                         ! normal exit
        end if

        if (fb == ZERO) then             ! Is the best approximate root b
                                         ! a precise root of f ?
          fehler = 1
          return                         ! other normal exit, b is a root
        end if

        r = ZERO

        if (DABS(e) < tol1.or.DABS(fa) <= DABS(fb)) then
          e = xm;
          d = e;
          write(2,*) ' Bisection'
        else
          if (a.ne.c) then       ! if a is not equal to c
            q = fa / fc          ! With a, b and c we have 3 points for
            r = fb / fc          ! an inverse quadratic interpolation
            s = fb / fa
            p = s * (TWO * xm * q * (q - r) - (b - a) * (r - ONE))
            q = (q - ONE) * (r - ONE) * (s - ONE)
          else                   ! If a equals  c :
            s = fb / fa          ! Use the secant method or linear
            p = TWO * xm * s     ! interpolation
            q = ONE - s
          end if

          if (p > ZERO) then     ! alter the sign of  p/q for the
            q = -q               ! subsequent division
          else
            p = DABS(p)
          end if 

          if (TWO * p  >=  THREE * xm * q - DABS(tol1 * q).or.p >= DABS(HALF * e * q)) then
            e = xm; d = e
            write(2,*) ' Bisection'
          else
            e = d        ! Compute the quotient p/q for both iterations
            d = p / q    ! which will be used to modify b
            if (r == ZERO) then
              write(2,*) ' Secant method'
            else
              write(2,*) ' Inverse quadratic interpolation'
            end if
          end if
        end if

        a  = b           ! store the best approximation b and its
        fa = fb          ! function value fb in a and fa

        if (DABS(d) > tol1) then                    ! d large enough?
          b = b + d                                 ! add d to b
          write(2,*) ' Difference d from new b: ', d
        else                                        ! d too small?
          b = b + Sign(tol1, xm)                    ! add tol1 to b
          if (xm < ZERO) then
            write(2,*) ' Subtract error bound: d = ', -tol1
          else
            write(2,*) ' Add error bound: d = ', tol1
          end if
        end if

        fb = Fkt( b )
        fanz=fanz+1                        !      up evaluation counter

        write(2,*) ' b = ',b,' fb= ', fb,' Number of functional evaluations = ', fanz

        if (fanz > fmax) then              ! too many function evaluations?
          fehler = 3
          goto 50
        end if
      end do                                                ! end iteration

    50 close(unit=2)

      rc = fehler

      ! construct function return type
      out_zeroin%root  = b
      out_zeroin%froot = fb
      out_zeroin%niter = fanz
      out_zeroin%error = rc

      return

    100 format(' a  = ', F20.14, ' b  = ', F20.14, ' c  = ', F20.14)
    110 format(' fa = ', F20.14, ' fb = ', F20.14, ' fc = ', F20.14)
    120 format(' xm = ', F20.14, ' tol1 = ', F20.14) 

  end function zeroin

end module
! ------------------------ end fzeroin.f90 -----------------------------

!*********************************************************************
!*   Find a real root of a real function F(x) by the Zeroin method   *
!* ----------------------------------------------------------------- *
!* SAMPLE RUN:                                                       *
!* (Find a root of function 5x - exp(x) between 0 and 1)             *
!*                                                                   *
!* The output file tzeroin.lst contains:                             *
!*                                                                   *
!* ----------------------------------------------------------------- *
!* Zeroin method for real valued, nonlinear functions                *
!*------------------------------------------------------------------ *
!* Find a real root of function:                                     *
!* F(x) = 5x - Exp(x)                                                *
!* Starting value x0 =  0.00000000000000E+0000                       *
!* Return code       = 0                                             *
!* Root              =     0.25917110181899                          *
!* Function value    =    -0.00000000000030                          *
!* Function calls    = 8                                             *
!* Absolute error    =     0.00000000010000                          *
!* Relative error    =     0.00000000100000                          *
!*------------------------------------------------------------------ *
!* Ref.: "Numerical Algorithms with C By G. Engeln-Mueller and       *
!*        F. Uhlig, Springer-Verlag, 1996" [BIBLI 11].               *
!*                                                                   *
!*                                F90 version by J-P Moreau, Paris.  *
!*                                       (www.jpmoreau.fr)           *
!*********************************************************************
Use Fzeroin
          
  integer i,rc,nmax,niter
  real*8  abserr, relerr, x1, x2, root, f
  type(outtype_zeroin) :: out_zeroin

! the subroutine Fkt(x,y) is defined in module Fzeroin.f90

  abserr=100.d0*XMACHEPS
  relerr=1000.d0*XMACHEPS

  open(unit=1,file='tzeroin.lst',status='unknown') 

  write(1,*) '----------------------------------------------------'
  write(1,*) ' Zeroin method for real valued, nonlinear functions '
  write(1,*) '----------------------------------------------------'

  nmax = 100; x1=ZERO; x2=ONE

  write(1,*) ' Find a real root of function:'
  write(1,*) ' F(x) = 5x - Exp(x)'
  write(1,*) ' Starting value x0 = ', x1

  ! call zeroin( abserr, relerr, nmax, 'tzeroin.log', x1, x2, root, f, niter, rc)

  root = zeroin( abserr, relerr, nmax, x1, x2, protnam='tzeroin.log' )

  write(1,*) ' Root              = ', root
  ! write(1,*) ' Return code       = ', out_zeroin%error
  ! write(1,*) ' Root              = ', out_zeroin%root
  ! write(1,*) ' Function value    = ', out_zeroin%froot
  ! write(1,*) ' Function calls    = ', out_zeroin%niter
  write(1,*) ' Absolute error    = ', abserr 
  write(1,*) ' Relative error    = ', relerr 
  write(1,*) '----------------------------------------------------'
      
  close(unit=1)

  print *,' '
  print *,' Results in tzeroin.lst.'
  print *,' '

END

!end of file tzeroin.f90