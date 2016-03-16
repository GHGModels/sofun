module _gpp
  !////////////////////////////////////////////////////////////////
  ! P-MODEL GPP MODULE
  ! Contains P model functions adopted from GePiSaT
  ! This module ontains the "main" subroutine 'pmodel' and all necessary 
  ! subroutines for handling input/output. 
  ! Every module that implements 'pmodel' must contain this list 
  ! of subroutines (names that way).
  !   - getpar_modl_gpp
  !   - initio_gpp
  !   - initoutput_gpp
  !   - getout_daily_gpp
  !   - writeout_ascii_gpp
  !   - pmodel
  ! Required module-independent model state variables (necessarily 
  ! updated by 'pmodel') are:
  !   - xxx
  ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
  ! contact: b.stocker@imperial.ac.uk
  !----------------------------------------------------------------
  use _params_core, only: nmonth, npft, c_molmass, h2o_molmass, maxgrid, ndayyear

  implicit none

  private
  public dgpp, dtransp, drd, getpar_modl_gpp, initio_gpp, initoutput_gpp, &
    initdaily_gpp, gpp, getlue, getout_daily_gpp, writeout_ascii_gpp

  !----------------------------------------------------------------
  ! Public, module-specific state variables
  !----------------------------------------------------------------
  real, dimension(npft) :: dgpp            ! gross primary production [gC/m2/d]
  real, dimension(npft) :: dtransp         ! daily transpiration [mm]
  real, dimension(npft) :: drd             ! dark respiration [gC/m2/d]
  real, dimension(npft) :: vcmax_canop     ! canopy-level Vcmax

  !----------------------------------------------------------------
  ! Module-specific output variables
  !----------------------------------------------------------------
  ! daily
  real, allocatable, dimension(:,:,:) :: outdgpp
  real, allocatable, dimension(:,:,:) :: outdrd
  real, allocatable, dimension(:,:,:) :: outdtransp

  ! monthly
  real, allocatable, dimension(:,:,:) :: outmgpp
  real, allocatable, dimension(:,:,:) :: outmrd
  real, allocatable, dimension(:,:,:) :: outmtransp

  ! annual
  real, dimension(npft,maxgrid) :: outagpp
  real, dimension(npft,maxgrid) :: outavcmax
  real, dimension(npft,maxgrid) :: outachi
  real, dimension(npft,maxgrid) :: outalue

  ! These are stored as dayly variables for annual output
  ! at day of year when LAI is at its maximum.
  real, dimension(npft,ndayyear) :: outdvcmax_canop

  !-----------------------------------------------------------------------
  ! Known parameters, therefore hard-wired.
  !-----------------------------------------------------------------------
  real, parameter :: kPo = 101325.0        ! standard atmosphere, Pa (Allen, 1973)
  real, parameter :: kTo = 25.0            ! base temperature, deg C (Prentice, unpublished)

  !-----------------------------------------------------------------------
  ! Metabolic N ratio (N per unit Vcmax)
  ! Reference: Harrison et al., 2009, Plant, Cell and Environment; Eq. 3
  !-----------------------------------------------------------------------
  real, parameter :: mol_weight_rubisco    = 5.5e5    ! molecular weight of Rubisco, (g R)(mol R)-1
  real, parameter :: n_conc_rubisco        = 1.14e-2  ! N concentration in rubisco, (mol N)(g R)-1
  real, parameter :: cat_turnover_per_site = 2.33     ! catalytic turnover rate per site at 25 deg C, (mol CO2)(mol R sites)-1; use 2.33 instead of (3.5) as not all Rubisco is active (see Harrison et al., 2009)  
  real, parameter :: cat_sites_per_mol_R   = 8.0      ! number of catalytic sites per mol R, (mol R sites)(mol R)-1

  ! Metabolic N ratio (mol N s (mol CO2)-1 )
  real, parameter :: n_v = mol_weight_rubisco * n_conc_rubisco / ( cat_turnover_per_site * cat_sites_per_mol_R )

  !-----------------------------------------------------------------------
  ! Uncertain (unknown) parameters. Runtime read-in
  !-----------------------------------------------------------------------
  type paramstype_gpp
    real :: rd_to_vcmax  ! Ratio of Rdark to Vcmax25, number from Atkin et al., 2015 for C3 herbaceous
    real :: beta         ! Unit cost of carboxylation (dimensionless)
  end type paramstype_gpp

  type( paramstype_gpp ) :: params_glob_gpp

  ! PFT-DEPENDENT PARAMETERS
  type pftparamstype_gpp
    real :: kphio        ! quantum efficiency (Long et al., 1993)  
  end type pftparamstype_gpp

  type( pftparamstype_gpp ), dimension(npft) :: params_pft_gpp
 
  !-----------------------------------------------------------------------
  ! Email from Tyler (10.3.2015):
  ! I was estimating values of β based on the Wang Han approximation equation 
  ! of χ using both the simplified and "more precise" expressions for χ and ξ 
  ! (Prentice et al., 2014, Ecology Letters).  After examination, Colin and I 
  ! noticed that the value of β is not significantly influenced by the 
  ! expressions for χ and ξ. Since then, Colin has theorised the use of a 
  ! "ground state" universal value of β, which is derived from the Wang Han 
  ! equation at sea level (i.e., z = 0 m and Patm = 101325 Pa), standard temp-
  ! erature (i.e., Tair = 25 deg C) and a non-influencial VPD (i.e., 
  ! D = 1000 Pa). Based on these climatological values, the following were 
  ! calculated:
  !   a. Γ* = 4.220 Pa
  !   b. K = 70.842 Pa
  !   c. η* = 1.0
  !   d. χ = 0.767
  !   e. β = 244.033
  ! Results from modelled versus "observed" monthly GPP based on the universal 
  ! value of β are promising. Colin and I are currently in the works on the next 
  ! set of improvements, which, as I far as I know, will be based on this uni-
  ! versal value of β.
  !-----------------------------------------------------------------------
  
  ! parameters for Narea -- under construction
  ! sla = 0.0014       ! specific leaf area (m2/gC)

  ! N in cell walls: Slope of WN~LMA is 0.0002 mol N / g leaf mass (Hikosaka&Shigeno, 2009)
  ! With 0.5 g C / g leaf mass and 14 g N / mol N: n_cw = 0.0056 g N / g C

  ! real, parameter :: ncw = 0.0056          ! N:C ratio in cell walls, working hypothesis: leaf N is solely determined by Vcmax25
  ! n_v  = 1.0/40.96    ! gN µmol-1 s-1. Value 40.96 is 'sv' in Table 2 in Kattge et al., 2009, GCB, C3 herbaceous
  ! -- under construction

  ! DAILY OUTPUT VARIABLES
  ! xxx add jpngr dim

  ! MONTHLY OUTPUT VARIABLES
  ! xxx add jpngr dim

  !----------------------------------------------------------------
  ! MODULE-SPECIFIC, PRIVATE VARIABLES
  !----------------------------------------------------------------
  real, dimension(npft,nmonth) :: mlue             ! Light use efficiency: (gpp - rd) per unit light absorbed
  real, dimension(npft,nmonth) :: mvcmax_unitiabs  ! Vcmax per unit fAPAR
  real, dimension(npft,nmonth) :: mactnv_unitiabs  ! conversion factor to get from APAR to Rubisco-N
  real, dimension(npft,nmonth) :: factor25         ! factor to convert from 25 deg-normalised to ambient T
  real, dimension(npft,nmonth) :: mrd_unitiabs     ! dark respiration per unit fAPAR (assuming fAPAR=1)
  real, dimension(npft,nmonth) :: mtransp_unitiabs ! transpiration per unit light absorbed [g H2O (mol photons)-1]
  real, dimension(npft,nmonth) :: mvcmax           ! Vcmax per unit ground area (mol m-2 s-1)
  ! real, dimension(npft,nmonth) :: mnrlarea         ! metabolic leaf Narea (active Rubisco-N) [gN/m2-leaf]
  real, dimension(npft,nmonth) :: mchi             ! chi = ci/ca, leaf internal-to-ambient CO2 partial pressure
  real, dimension(npft)        :: avcmax           ! Vcmax per unit ground area (mol m-2 s-1); annual value is maximum of monthly values
  ! real                    :: anrlarea         ! metabolic leaf Narea (active Rubisco-N) [gN/m2-leaf]; annual value is maximum of monthly values

  ! Function return variables as derived types
  type outtype_pmodel
    real :: gpp
    real :: gstar
    real :: chi
    real :: vcmax
    real :: vcmax25
    real :: vcmax_unitfapar
    real :: vcmax_unitiabs
    real :: factor25_vcmax
    real :: rd
    real :: rd_unitfapar 
    real :: rd_unitiabs 
    real :: actnv 
    real :: actnv_unitfapar 
    real :: actnv_unitiabs 
    real :: lue
    real :: transp          
    real :: transp_unitfapar
    real :: transp_unitiabs 
  end type outtype_pmodel

  type outtype_lue
    real :: chi
    real :: m
    real :: n
  end type outtype_lue

contains

  subroutine gpp( jpngr, doy, moy, fapar_prescr )
    !//////////////////////////////////////////////////////////////////
    ! Calculates daily GPP (gC/m2/d) from monthly acclimated photosynth-
    ! etic parameters (P-model output) and actual daily PPFD and soil
    ! moisture stress (Cramer-Prentice Alpha).
    ! Alternatively ready from data (prescribed GPP array).
    !
    ! Output:   
    ! - gpp (gC/m2/d)   : gross primary production
    !
    !------------------------------------------------------------------
    use _params_core, only: dummy
    use _vars_core, only: fapar_ind
    use _waterbal, only: solar

    ! arguments
    integer, intent(in) :: jpngr     ! gridcell number
    integer, intent(in) :: doy       ! day of year and month of year
    integer, intent(in) :: moy       ! month of year and month of year

    ! optional arguments (may be dummy)
    real, intent(in) :: fapar_prescr

    ! local variables
    integer :: pft

    !----------------------------------------------------------------
    ! CALCULATE PREDICTED GPP FROM P-model
    ! using instantaneous (daily) LAI, PPFD, Cramer-Prentice-alpha
    !----------------------------------------------------------------
    do pft=1,npft

      ! Override interactively simulated fAPAR with data
      if (fapar_prescr/=dummy) fapar_ind(pft,jpngr) = fapar_prescr

      if (fapar_ind(pft,jpngr)>0.0) then

        ! fapar_ind(pft,jpngr) = 1.0
        ! write(0,*) 'in SR gpp: fapar          ', fapar_ind(pft,jpngr) !OK!
        ! write(0,*) 'in SR gpp: doy, solar%dppfd(doy)', doy, solar%dppfd(doy) !OK!
        ! write(0,*) 'in SR gpp: moy, mlue(pft,moy) ', moy, mlue(pft,moy) !OK! 
        ! dgpp(pft)    = calc_dgpp( fapar_ind(pft,jpngr), solar%dppfd(doy), mlue(pft,moy) )
        dgpp(pft)    = calc_dgpp( fapar_ind(pft,jpngr), solar%dppfd(doy), mlue(pft,moy) )

        ! Dark respiration
        drd(pft)     = calc_drd( fapar_ind(pft,jpngr), solar%meanmppfd(moy), mrd_unitiabs(pft,moy) )
        ! drd(pft)     = calc_drd( 0.05, solar%meanmppfd(moy), mrd_unitiabs(pft,moy) )
        ! write(0,*) 'doy, drd(pft)             ', doy, drd(pft)

        ! transpiration
        dtransp(pft) = calc_dtransp( fapar_ind(pft,jpngr), solar%dppfd(doy), mtransp_unitiabs(pft,moy) )
        ! dtransp(pft) = calc_dtransp( 0.05, solar%dppfd(doy), mtransp_unitiabs(pft,moy) )

        ! Vcmax
        vcmax_canop(pft) = calc_vcmax_canop( fapar_ind(pft,jpngr), mvcmax_unitiabs(pft,moy), solar%meanmppfd(moy) )
        ! mvcmax(moy)   = calc_vcmax(    max_lai, mvcmax_unitiabs(pft,moy), solar%meanmppfd(moy) )


      else  

        dgpp(pft)    = 0.0
        drd(pft)     = 0.0
        dtransp(pft) = 0.0

      end if 

    end do

    ! write(0,*) '---in gpp: '
    ! write(0,*) 'fapar_ind(pft,jpngr) ',fapar_ind
    ! write(0,*) 'solar%dppfd(doy) ',solar%dppfd(doy)
    ! write(0,*) 'mlue(pft,moy) ',mlue(pft,moy)
    ! write(0,*) 'solar%meanmppfd(moy) ',solar%meanmppfd(moy)
    ! write(0,*) 'mrd_unitiabs(moy) ',mrd_unitiabs(moy)
    ! write(0,*) 'dgpp(pft) ',dgpp
    ! write(0,*) 'drd(pft)  ',drd

    ! write(0,*) 'dgpp', dgpp
    ! write(0,*) 'sum(dppfd)',sum(dppfd)
    ! stop

  end subroutine gpp


  subroutine getlue( jpngr, co2, dtemp, dvpd, elv )
    !//////////////////////////////////////////////////////////////////
    ! Calculates the monthly acclimated photosynthetic parameters for 
    ! assimilation, Vcmax, and dark respiration per unit light absorbed.
    ! This SR is called before the daily loop. This implies that all 
    ! input variables need to be known beforehand => no daily coupling
    ! possible.
    !------------------------------------------------------------------
    use _params_core, only: ndayyear, nlu
    use _sofunutils, only: daily2monthly
    use _waterbal, only: evap

    ! arguments
    integer, intent(in)                   :: jpngr    ! gridcell number
    real, intent(in)                      :: co2      ! atmospheric CO2 (ppm)
    real, dimension(ndayyear), intent(in) :: dtemp    ! daily air temperature (deg C)
    real, dimension(ndayyear), intent(in) :: dvpd     ! daily vapour pressure deficit (Pa)
    real, intent(in)                      :: elv      ! elevation above sea level (m)

    ! local variables
    type(outtype_pmodel)    :: out_pmodel ! derived type for P-model output variable list
    real, dimension(nmonth) :: mtemp      ! monthly air temperature (deg C)
    real, dimension(nmonth) :: mvpd       ! monthly vapour pressure deficit (Pa)
    integer                 :: moy, lu, pft

    ! Get monthly averages
    mtemp(:) = daily2monthly( dtemp(:), "mean" )
    mvpd(:)  = daily2monthly( dvpd(:), "mean" )

    ! xxx try out: -- THIS WORKS PERFECTLY -- 
    ! write(0,*) 'WARNING: TEST INPUT FOR COMPARISON WITH OPTI7.R'
    ! co2   = 376.0
    ! elv   = 450.0
    ! mtemp = (/0.4879904, 6.1999985, 7.4999870, 9.6999003, 13.1999913, 19.6999227, 18.6000030, 18.0999577, 13.8999807, 10.7000307, 7.2999217, 4.4999644/)
    ! mvpd  = (/113.0432, 338.4469, 327.1185, 313.8799, 247.9747, 925.9489, 633.8551, 497.6772, 168.7784, 227.1889, 213.0142, 172.6035/)
    ! mppfd = (/223.8286, 315.2295, 547.4822, 807.4035, 945.9020, 1194.1227, 1040.5228, 1058.4161, 814.2580, 408.5199, 268.9183, 191.4482/)

    ! write(0,*) 'co2'
    ! write(0,*) co2
    ! write(0,*) 'mtemp'
    ! write(0,*) mtemp
    ! write(0,*) 'mvpd'
    ! write(0,*) mvpd
    ! stop

    ! Run P-model for monthly averages and store monthly variables 
    ! per unit absorbed light (not corrected for soil moisture)

    ! XXX PMODEL_TEST
    write(0,*) 'WARNING: CRAMER-PRENTICE ALPHA = 1.26 USED IN PMODEL'

    do lu=1,nlu

      if (lu>1) stop 'in GETLUE(): think of something about LU and PFTs!'

      do pft=1,npft

        do moy=1,nmonth

          ! Execute P-model not declaring fAPAR and PPFD, and cpalpha=1.26
          out_pmodel = pmodel( pft, -9999.0, -9999.0, co2, mtemp(moy), evap(lu)%cpa, mvpd(moy), elv, "full" )
          ! out_pmodel                = pmodel( pft, -9999.0, -9999.0, co2, mtemp(moy), 1.26, mvpd(moy), elv, "full" )
          ! out_pmodel                = pmodel( pft, -9999.0, -9999.0, co2, mtemp(moy), 1.26, mvpd(moy), elv, "approx" )

          ! Light use efficiency: (gpp - rd) per unit light absorbed
          mlue(pft,moy)             = out_pmodel%lue
          ! write(0,*) 'moy, mlue', moy, mlue(moy)
          
          ! Vcmax per unit absorbed light
          mvcmax_unitiabs(pft,moy)  = out_pmodel%vcmax_unitiabs
          
          ! conversion factor to get from absorbed light to Rubisco-N
          mactnv_unitiabs(pft,moy)  = out_pmodel%actnv_unitiabs
          
          ! factor to convert from 25 deg-normalised to ambient T
          factor25(pft,moy)         = out_pmodel%factor25_vcmax
          
          ! dark respiration per unit absorbed light
          mrd_unitiabs(pft,moy)     = out_pmodel%rd_unitiabs

          ! transpiration per unit 
          mtransp_unitiabs(pft,moy) = out_pmodel%transp_unitiabs

          ! ci:ca
          mchi(pft,moy)             = out_pmodel%chi

        end do
      end do
    end do

    ! xxx debug
    ! write(0,*) 'mtemp', mtemp
    ! write(0,*) 'mvpd', mvpd
    ! write(0,*) 'co2', co2
    ! write(0,*) 'elv', elv
    ! write(0,*) 'mlue', mlue
    ! write(0,*) 'mvcmax_unitiabs', mvcmax_unitiabs
    ! write(0,*) 'mactnv_unitiabs', mactnv_unitiabs
    ! write(0,*) 'factor25', factor25
    ! write(0,*) 'mrd_unitiabs', mrd_unitiabs
    ! write(0,*) 'mchi', mchi
    ! stop

  end subroutine getlue


  function calc_dgpp( fapar, dppfd, my_mlue ) result( my_dgpp )
    !//////////////////////////////////////////////////////////////////
    ! Calculates daily GPP
    !------------------------------------------------------------------
    ! arguments
    real, intent(in) :: fapar
    real, intent(in) :: dppfd
    real, intent(in) :: my_mlue

    ! function return variable
    real, intent(out) :: my_dgpp

    ! GPP is light use efficiency multiplied by absorbed light and C-P-alpha
    my_dgpp = fapar * dppfd * my_mlue * c_molmass

  end function calc_dgpp


  function calc_drd( fapar, meanmppfd, my_mrd_unitiabs ) result( my_drd )
    !//////////////////////////////////////////////////////////////////
    ! Calculates daily dark respiration (Rd) based on monthly mean 
    ! PPFD (assumes acclimation on a monthly time scale).
    !------------------------------------------------------------------
    ! arguments
    real, intent(in) :: fapar           ! fraction of absorbed PAR (unitless)
    real, intent(in) :: meanmppfd       ! monthly mean PPFD (mol m-2 s-1)
    real, intent(in) :: my_mrd_unitiabs

    ! function return variable
    real, intent(out) :: my_drd

    ! Dark respiration takes place during night and day (24 hours)
    my_drd = fapar * meanmppfd * my_mrd_unitiabs * 60.0 * 60.0 * 24.0 * c_molmass

  end function calc_drd


  function calc_dtransp( fapar, dppfd, my_transp_unitiabs ) result( my_dtransp )
    !//////////////////////////////////////////////////////////////////
    ! Calculates daily GPP
    !------------------------------------------------------------------
    ! arguments
    real, intent(in) :: fapar
    real, intent(in) :: dppfd
    real, intent(in) :: my_transp_unitiabs

    ! function return variable
    real, intent(out) :: my_dtransp

    ! GPP is light use efficiency multiplied by absorbed light and C-P-alpha
    my_dtransp = fapar * dppfd * my_transp_unitiabs * h2o_molmass

  end function calc_dtransp


  function calc_vcmax_canop( fapar, my_vcmax_unitiabs, meanmppfd ) result( my_vcmax )
    !//////////////////////////////////////////////////////////////////
    ! Calculates leaf-level metabolic N content per unit leaf area as a
    ! function of Vcmax25.
    !------------------------------------------------------------------
    ! arguments
    real, intent(in) :: fapar
    real, intent(in) :: my_vcmax_unitiabs
    real, intent(in) :: meanmppfd

    ! function return variable
    real, intent(out) :: my_vcmax

    ! Calculate leafy-scale Rubisco-N as a function of LAI and current LUE
    my_vcmax = fapar * meanmppfd * my_vcmax_unitiabs

  end function calc_vcmax_canop


  function pmodel( pft, fpar, ppfd, co2, tc, cpalpha, vpd, elv, method ) result( out_pmodel )
    !//////////////////////////////////////////////////////////////////
    ! Output:   gpp (mol/m2/month)   : gross primary production
    !------------------------------------------------------------------

    ! arguments
    integer, intent(in) :: pft         
    real, intent(in)    :: fpar         ! monthly fraction of absorbed photosynthetically active radiation (unitless) 
    real, intent(in)    :: ppfd         ! monthly photon flux density (mol/m2)
    real, intent(in)    :: co2          ! atmospheric CO2 concentration (ppm)
    real, intent(in)    :: tc           ! monthly air temperature (deg C)
    real, intent(in)    :: cpalpha      ! monthly Cramer-Prentice-alpha (unitless, within [0,1.26]) 
    real, intent(in)    :: vpd          ! mean monthly vapor pressure (Pa) -- CRU data is in hPa
    real, intent(in)    :: elv          ! elevation above sea-level (m)
    character(len=*), intent(in) :: method

    ! function return value
    type(outtype_pmodel), intent(out) :: out_pmodel

    ! local variables
    real :: iabs                     ! absorbed photosynthetically active radiation (mol/m2)
    real :: patm                     ! atmospheric pressure as a function of elevation (Pa)
    real :: ca                       ! ambient CO2 partial pression (Pa)
    real :: ci                       ! leaf-internal CO2 partial pression, (Pa)
    real :: chi                      ! leaf-internal to ambient CO2 partial pression, ci/ca (unitless)
    real :: gs                       ! stomatal conductance
    real :: gstar                    ! photorespiratory compensation point - Gamma-star (Pa)
    real :: fa                       ! function of alpha to reduce GPP in strongly water-stressed months (unitless)
    real :: kmm                      ! Michaelis-Menten coefficient (Pa)
    real :: ns                       ! viscosity of H2O at ambient temperatures (Pa s)
    real :: ns25                     ! viscosity of H2O at 25 deg C (Pa s)
    real :: ns_star                  ! viscosity correction factor (unitless)
    real :: m
    real :: n
    real :: gpp                      ! assimilation (mol m-2 s-1)
    real :: lue                      ! Light use efficiency
    real :: vcmax                    ! Vcmax per unit ground area (mol m-2 s-1)
    real :: vcmax_unitfapar
    real :: vcmax_unitiabs
    real :: vcmax25                  ! Vcmax25 (vcmax normalized to 25 deg C)
    real :: vcmax25_unitfapar
    real :: vcmax25_unitiabs
    real :: rd                       ! Dark respiration (mol m-2 s-1)
    real :: rd_unitfapar 
    real :: rd_unitiabs 
    real :: factor25_vcmax           ! correction factor to normalise Vcmax to 25 deg C
    real :: actnv 
    real :: actnv_unitfapar 
    real :: actnv_unitiabs 
    real :: transp          
    real :: transp_unitfapar
    real :: transp_unitiabs 

    type(outtype_lue) :: out_lue


    ! absorbed photosynthetically active radiation (mol/m2)
    iabs = fpar * ppfd

    ! atmospheric pressure as a function of elevation (Pa)
    patm = calc_patm( elv )

    ! ambient CO2 partial pression (Pa)
    ca   = co2_to_ca( co2, patm )

    ! photorespiratory compensation point - Gamma-star (Pa)
    gstar   = calc_gstar( tc )

    ! ! XXX PMODEL_TEST: ok
    ! write(0,*) 'gstar ', gstar

    ! function of alpha to reduce GPP in strongly water-stressed months (unitless)
    fa   = calc_fa( cpalpha )

    ! Michaelis-Menten coef. (Pa)
    kmm  = calc_k( tc, patm )

    ! ! XXX PMODEL_TEST: ok
    ! write(0,*) 'kmm ', kmm

    ! viscosity correction factor = viscosity( temp, press )/viscosity( 25 degC, 1013.25 Pa) 
    ns      = calc_viscosity_h2o( tc, patm )  ! Pa s 
    ns25    = calc_viscosity_h2o( kTo, kPo )  ! Pa s 
    ns_star = ns / ns25                       ! (unitless)

    ! ! XXX PMODEL_TEST: ok
    ! write(0,*) 'ns ', ns

    select case (method)

      case ("approx")
        !-----------------------------------------------------------------------
        ! A. APPROXIMATIVE METHOD
        !-----------------------------------------------------------------------
        out_lue = lue_approx( tc, vpd, elv, ca, gstar, ns, kmm )
                  
      case ("simpl")
        !-----------------------------------------------------------------------
        ! B.1 SIMPLIFIED FORMULATION 
        !-----------------------------------------------------------------------
        out_lue = lue_vpd_simpl( kmm, gstar, ns, ca, vpd )

      case ("full")
        !-----------------------------------------------------------------------
        ! B.2 FULL FORMULATION
        !-----------------------------------------------------------------------
        out_lue = lue_vpd_full( kmm, gstar, ns_star, ca, vpd )

      case default

        stop 'PMODEL: select valid method'

    end select

    ! LUE-functions return m, n, and chi
    m   = out_lue%m
    n   = out_lue%n
    chi = out_lue%chi

    ! ! XXX PMODEL_TEST: ok
    ! write(0,*) 'chi ', chi

    !-----------------------------------------------------------------------
    ! Calculate function return variables
    !-----------------------------------------------------------------------

    ! GPP per unit ground area is the product of the intrinsic quantum 
    ! efficiency, the absorbed PAR, the function of alpha (drought-reduction),
    ! and 'm'
    m   = calc_mprime( m )
    gpp = iabs * params_pft_gpp(pft)%kphio * fa * m  ! in mol m-2 s-1

    ! Light use efficiency (gpp per unit iabs)
    lue = params_pft_gpp(pft)%kphio * fa * m 

    ! ! XXX PMODEL_TEST: ok
    ! write(0,*) 'lue ', lue

    ! leaf-internal CO2 partial pressure (Pa)
    ci = chi * ca

    ! stomatal conductance
    gs = gpp  / ( ca - ci )

    ! Vcmax per unit ground area is the product of the intrinsic quantum 
    ! efficiency, the absorbed PAR, and 'n'
    vcmax = iabs * params_pft_gpp(pft)%kphio * n

    ! Vcmax normalised per unit fAPAR (assuming fAPAR=1)
    vcmax_unitfapar = ppfd * params_pft_gpp(pft)%kphio * n 

    ! Vcmax normalised per unit absorbed PPFD (assuming iabs=1)
    vcmax_unitiabs = params_pft_gpp(pft)%kphio * n 

    ! Vcmax25 (vcmax normalized to 25 deg C)
    factor25_vcmax    = calc_vcmax25( 1.0, tc )
    vcmax25           = factor25_vcmax * vcmax
    vcmax25_unitfapar = factor25_vcmax * vcmax_unitfapar
    vcmax25_unitiabs  = factor25_vcmax * vcmax_unitiabs

    ! Dark respiration
    rd = params_glob_gpp%rd_to_vcmax * vcmax

    ! Dark respiration per unit fAPAR (assuming fAPAR=1)
    rd_unitfapar = params_glob_gpp%rd_to_vcmax * vcmax_unitfapar

    ! Dark respiration per unit absorbed PPFD (assuming iabs=1)
    rd_unitiabs = params_glob_gpp%rd_to_vcmax * vcmax_unitiabs

    ! active metabolic leaf N (canopy-level), mol N/m2-ground (same equations as for nitrogen content per unit leaf area, gN/m2-leaf)
    actnv = vcmax25 * n_v
    actnv_unitfapar = vcmax25_unitfapar * n_v
    actnv_unitiabs  = vcmax25_unitiabs  * n_v

    ! Transpiration (E)
    ! Using 
    ! - E = 1.6 gs D
    ! - gs = A / (ca (1-chi))
    ! (- chi = ci / ca)
    ! => E = f
    transp           = (1.6 * iabs * params_pft_gpp(pft)%kphio * fa * m * vpd) / (ca - ci)   ! gpp = iabs * params_pft_gpp(pft)%kphio * fa * m
    transp_unitfapar = (1.6 * ppfd * params_pft_gpp(pft)%kphio * fa * m * vpd) / (ca - ci)
    transp_unitiabs  = (1.6 * 1.0  * params_pft_gpp(pft)%kphio * fa * m * vpd) / (ca - ci)

    ! Construct derived type for output
    out_pmodel%gpp              = gpp
    out_pmodel%gstar            = gstar
    out_pmodel%chi              = chi
    out_pmodel%vcmax            = vcmax
    out_pmodel%vcmax25          = vcmax25
    out_pmodel%vcmax_unitfapar  = vcmax_unitfapar
    out_pmodel%vcmax_unitiabs   = vcmax_unitiabs
    out_pmodel%factor25_vcmax   = factor25_vcmax
    out_pmodel%rd               = rd
    out_pmodel%rd_unitfapar     = rd_unitfapar 
    out_pmodel%rd_unitiabs      = rd_unitiabs 
    out_pmodel%actnv            = actnv 
    out_pmodel%actnv_unitfapar  = actnv_unitfapar 
    out_pmodel%actnv_unitiabs   = actnv_unitiabs 
    out_pmodel%lue              = lue
    out_pmodel%transp           = transp          
    out_pmodel%transp_unitfapar = transp_unitfapar
    out_pmodel%transp_unitiabs  = transp_unitiabs 
    
  end function pmodel


  subroutine getpar_modl_gpp()
    !////////////////////////////////////////////////////////////////
    ! Subroutine reads waterbalance module-specific parameters 
    ! from input file
    !----------------------------------------------------------------
    use _sofunutils, only: getparreal
    use _params_site, only: lTeBS, lGrC3, lGrC4

    ! local variables
    integer :: pft

    !----------------------------------------------------------------
    ! PFT-independent parameters
    !----------------------------------------------------------------
    ! unit cost of carboxylation
    params_glob_gpp%beta  = getparreal( 'params/params_gpp_pmodel.dat', 'beta' )

    ! Ratio of Rdark to Vcmax25, number from Atkin et al., 2015 for C3 herbaceous
    params_glob_gpp%rd_to_vcmax  = getparreal( 'params/params_gpp_pmodel.dat', 'rd_to_vcmax' )

    !----------------------------------------------------------------
    ! PFT-dependent parameters
    !----------------------------------------------------------------
    pft = 0
    if ( lTeBS ) then
      pft = pft + 1
      params_pft_gpp(pft) = getpftparams_gpp( 'TeBS' )
    end if
    if ( lGrC3 ) then
      pft = pft + 1
      params_pft_gpp(pft) = getpftparams_gpp( 'GrC3' )
    end if
    if ( lGrC4 ) then
      pft = pft + 1
      params_pft_gpp(pft) = getpftparams_gpp( 'GrC4' )
    end if

  end subroutine getpar_modl_gpp


  function getpftparams_gpp( pftname ) result( out_getpftpar )
    !----------------------------------------------------------------
    ! Read PFT parameters from respective file, given the PFT name
    !----------------------------------------------------------------
    use _sofunutils, only: getparreal

    ! arguments
    character(len=*) :: pftname

    ! function return variable
    type( pftparamstype_gpp ) out_getpftpar

    ! leaf decay constant, read in as [years-1], central value: 0.0 yr-1 for deciduous plants
    out_getpftpar%kphio = getparreal( trim('params/params_gpp_pft_'//pftname//'_pmodel.dat'), 'kphio' )

  end function getpftparams_gpp


  function lue_approx( temp, vpd, elv, ca, gstar, ns_star, kmm ) result( out_lue )
    !//////////////////////////////////////////////////////////////////
    ! Output:   list: 'm' (unitless), 'chi' (unitless)
    ! Returns list containing light use efficiency (m) and ci/ci ratio 
    ! (chi) based on the approximation of the theoretical relationships
    ! of chi with temp, vpd, and elevation. Is now based on SI units as 
    ! inputs.
    !------------------------------------------------------------------

    ! arguments
    real, intent(in) :: temp      ! deg C, air temperature
    real, intent(in) :: vpd       ! Pa, vapour pressure deficit
    real, intent(in) :: elv       ! m, elevation above sea level
    real, intent(in) :: ca        ! Pa, ambient CO2 partial pressure
    real, intent(in) :: gstar ! Pa, photores. comp. point (Gamma-star)
    real, intent(in) :: ns_star   ! (unitless) viscosity correction factor for water
    real, intent(in) :: kmm       ! Pa, Michaelis-Menten coeff.

    ! function return value
    type(outtype_lue) :: out_lue

    ! local variables
    ! real :: beta_wh
    real :: whe                ! value of "Wang-Han Equation"
    real :: gamma
    real :: chi                ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio (unitless)
    real :: m

    ! ! variable substitutes
    ! real :: vdcg, vacg, vbkg, vsr

    ! Wang-Han Equation
    whe = exp( &
      1.19 &
      + 0.0545 * ( temp - 25.0 ) &
      - 0.5 * log( vpd ) &   ! convert vpd from Pa to kPa 
      - 8.15e-5 * elv &      ! convert elv from m to km
      )

    ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio
    chi = whe / ( 1.0 + whe )

    !  m
    gamma = gstar / ca
    m = (chi - gamma) / (chi + 2 * gamma)

    ! xxx try
    ! ! beta derived from chi and xi (see Estimation_of_beta.pdf). Uses empirical chi
    ! beta_wh = ( 1.6 * ns_star * vpd * ( chi * ca - gstar )**2 ) / ( ca**2 * ( chi - 1.0 )**2 * ( kmm + gstar ) )

    ! ! Define variable substitutes:
    ! vdcg = ca - gstar
    ! vacg = ca + 2.0 * gstar
    ! vbkg = beta_wh * (kmm + gstar)

    ! ! Check for negatives:
    ! if (vbkg > 0) then
    !   vsr = sqrt( 1.6 * ns_star * vpd / vbkg )

    !   ! Based on the m' formulation (see Regressing_LUE.pdf)
    !   m = vdcg / ( vacg + 3.0 * gstar * vsr )
    ! end if
    ! xxx

    ! return derived type
    out_lue%chi = chi
    out_lue%m = m
    out_lue%n = -9999
  
  end function lue_approx


  function lue_vpd_simpl( kmm, gstar, ns_star, ca, vpd ) result( out_lue )
    !//////////////////////////////////////////////////////////////////
    ! Output:   float, ratio of ci/ca (chi)
    ! Returns an estimate of leaf internal to ambient CO2
    ! partial pressure following the "simple formulation".
    !-----------------------------------------------------------------------

    ! arguments
    real, intent(in) :: kmm       ! Pa, Michaelis-Menten coeff.
    real, intent(in) :: gstar        ! Pa, photores. comp. point (Gamma-star)
    real, intent(in) :: ns_star   ! (unitless) viscosity correction factor for water
    real, intent(in) :: ca        ! Pa, ambient CO2 partial pressure
    real, intent(in) :: vpd       ! Pa, vapor pressure deficit

    ! function return value
    type(outtype_lue) :: out_lue

    ! local variables
    real :: xi
    real :: gamma
    real :: kappa
    real :: chi                   ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio (unitless)
    real :: m
    real :: n

    ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio
    xi  = sqrt( params_glob_gpp%beta * kmm / (1.6 * ns_star))
    chi = xi / (xi + sqrt(vpd))

    ! light use efficiency (m)
    ! consistent with this, directly return light-use-efficiency (m)
    m = ( xi * (ca - gstar) - gstar * sqrt( vpd ) ) / ( xi * (ca + 2.0 * gstar) + 2.0 * gstar * sqrt( vpd ) )

    ! n 
    gamma = gstar / ca
    kappa = kmm / ca
    n = (chi + kappa) / (chi + 2 * gamma)

    ! return derived type
    out_lue%chi=chi
    out_lue%m=m
    out_lue%n=n
      
  end function lue_vpd_simpl


  function lue_vpd_full( kmm, gstar, ns_star, ca, vpd ) result( out_lue )
    !//////////////////////////////////////////////////////////////////
    ! Output:   float, ratio of ci/ca (chi)
    ! Features: Returns an estimate of leaf internal to ambient CO2
    !           partial pressure following the "simple formulation".
    !-----------------------------------------------------------------------

    ! arguments
    real, intent(in) :: kmm       ! Pa, Michaelis-Menten coeff.
    real, intent(in) :: gstar        ! Pa, photores. comp. point (Gamma-star)
    real, intent(in) :: ns_star   ! (unitless) viscosity correction factor for water
    real, intent(in) :: ca        ! Pa, ambient CO2 partial pressure
    real, intent(in) :: vpd       ! Pa, vapor pressure deficit

    ! function return value
    type(outtype_lue) :: out_lue

    ! local variables
    real :: chi                   ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio (unitless)
    real :: xi
    real :: gamma
    real :: kappa
    real :: m
    real :: n

    ! variable substitutes
    real :: vdcg, vacg, vbkg, vsr

    ! beta = 1.6 * ns_star * vpd * (chi * ca - gstar) ** 2.0 / ( (kmm + gstar) * (ca ** 2.0) * (chi - 1.0) ** 2.0 )   ! see Estimation_of_beta.pdf

    ! leaf-internal-to-ambient CO2 partial pressure (ci/ca) ratio
    xi  = sqrt( ( params_glob_gpp%beta * ( kmm + gstar ) ) / ( 1.6 * ns_star ) )     ! see Eq. 2 in 'Estimation_of_beta.pdf'
    chi = gstar / ca + ( 1.0 - gstar / ca ) * xi / ( xi + sqrt(vpd) )  ! see Eq. 1 in 'Estimation_of_beta.pdf'

    ! consistent with this, directly return light-use-efficiency (m)
    ! see Eq. 13 in 'Simplifying_LUE.pdf'

    ! light use efficiency (m)
    ! m = (ca - gstar)/(ca + 2.0 * gstar + 3.0 * gstar * sqrt( (1.6 * vpd) / (beta * (K + gstar) / ns_star ) ) )

    ! Define variable substitutes:
    vdcg = ca - gstar
    vacg = ca + 2.0 * gstar
    vbkg = params_glob_gpp%beta * (kmm + gstar)

    ! Check for negatives:
    if (vbkg > 0) then
      vsr = sqrt( 1.6 * ns_star * vpd / vbkg )

      ! Based on the m' formulation (see Regressing_LUE.pdf)
      m = vdcg / ( vacg + 3.0 * gstar * vsr )
    end if

    ! n 
    gamma = gstar / ca
    kappa = kmm / ca
    n = (chi + kappa) / (chi + 2 * gamma)

    ! return derived type
    out_lue%chi=chi
    out_lue%m=m
    out_lue%n=n
  
  end function lue_vpd_full


  function calc_mprime( m ) result( mprime )
    !-----------------------------------------------------------------------
    ! Input:  m   (unitless): factor determining LUE
    ! Output: mpi (unitless): modiefied m accounting for the co-limitation
    !                         hypothesis after Prentice et al. (2014)
    !-----------------------------------------------------------------------
    ! argument
    real, intent(in) :: m

    ! local variables
    real, parameter :: kc = 0.41          ! Jmax cost coefficient

    ! function return variable
    real, intent(out) :: mprime

    ! square of m-prime (mpi)
    mprime = m**2 - kc**(2.0/3.0) * (m**(4.0/3.0))

    ! Check for negatives and take root of square
    if (mprime > 0) mprime = sqrt(mprime) 
    
  end function calc_mprime


  function calc_fa( cpalpha ) result( fa )
    !-----------------------------------------------------------------------
    ! Input:  cpalpha (unitless, within [0,1.26]): monthly Cramer-Prentice-alpha
    ! Output: fa (unitless, within [0,1]): function of alpha to reduce GPP 
    !                                      in strongly water-stressed months
    !-----------------------------------------------------------------------
    ! argument
    real, intent(in) :: cpalpha

    ! function return variable
    real, intent(out) :: fa

    fa = ( cpalpha / 1.26 )**(0.25)
    
  end function calc_fa


  function co2_to_ca( co2, patm ) result( ca )
    !-----------------------------------------------------------------------
    ! Output:   - ca in units of Pa
    ! Features: Converts ca (ambient CO2) from ppm to Pa.
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: co2     ! ambient CO2 in units of ppm
    real, intent(in) :: patm    ! monthly atm. pressure, Pa

    ! function return variable
    real, intent(out) :: ca ! ambient CO2 in units of Pa

    ca = ( 1.e-6 ) * co2 * patm         ! Pa, atms. CO2
      
  end function co2_to_ca


  function ca_to_co2( ca, patm ) result( co2 )
    !-----------------------------------------------------------------------
    ! Output:   - co2 in units of Pa
    ! Features: Converts ca (ambient CO2) from Pa to ppm.
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: ca        ! ambient CO2 in units of Pa
    real, intent(in) :: patm      ! monthly atm. pressure, Pa

    ! function return variable
    real, intent(out) :: co2

    co2   = ca * ( 1.e6 ) / patm
    
  end function ca_to_co2


  function calc_k( tc, patm ) result( k )
    !-----------------------------------------------------------------------
    ! Features: Returns the temperature & pressure dependent Michaelis-Menten
    !           coefficient, K (Pa).
    ! Ref:      Bernacchi et al. (2001), Improved temperature response 
    !           functions for models of Rubisco-limited photosynthesis, 
    !           Plant, Cell and Environment, 24, 253--259.
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: tc               ! air temperature, deg C 
    real, intent(in) :: patm             ! atmospheric pressure, Pa

    ! local variables
    real, parameter :: kc25 = 39.97      ! Pa, assuming 25 deg C & 98.716 kPa
    real, parameter :: ko25 = 2.748e4    ! Pa, assuming 25 deg C & 98.716 kPa
    real, parameter :: dhac = 79430      ! J/mol
    real, parameter :: dhao = 36380      ! J/mol
    real, parameter :: kR   = 8.3145     ! J/mol/K
    real, parameter :: kco  = 2.09476e5  ! ppm, US Standard Atmosphere

    real :: kc, ko, po

    ! function return variable
    real, intent(out) :: k               ! temperature & pressure dependent Michaelis-Menten coefficient, K (Pa).

    kc = kc25 * exp( dhac * (tc - 25.0)/(298.15 * kR * (tc + 273.15)) ) 
    ko = ko25 * exp( dhao * (tc - 25.0)/(298.15 * kR * (tc + 273.15)) ) 

    po     = kco * (1e-6) * patm ! O2 partial pressure
    k      = kc * (1.0 + po/ko)

  end function calc_k


  function calc_gstar( tc ) result( gstar )
    !-----------------------------------------------------------------------
    ! Features: Returns the temperature-dependent photorespiratory 
    !           compensation point, Gamma star (Pascals), based on constants 
    !           derived from Bernacchi et al. (2001) study. Corresponds
    !           to 'calc_gstar_colin' in pmodel.R.
    ! Ref:      Colin's document
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: tc             ! air temperature (degrees C)

    ! local variables
    real, parameter :: gs25 = 4.220    ! Pa, assuming 25 deg C & 98.716 kPa)
    real, parameter :: kR   = 8.3145   ! J/mol/K
    real, parameter :: dha  = 37830    ! J/mol

    real :: tk                         ! air temperature (Kelvin)

    ! function return variable
    real, intent(out) :: gstar   ! gamma-star (Pa)

    !! conversion to temperature in Kelvin
    tk = tc + 273.15

    gstar = gs25 * exp( ( dha / kR ) * ( 1.0/298.15 - 1.0/tk ) )
    
  end function calc_gstar


  function calc_vcmax25( vcmax, tc ) result( vcmax25 )
    !-----------------------------------------------------------------------
    ! Output:   vcmax25  : Vcmax at 25 deg C
    ! Features: Returns the temperature-corrected Vcmax at 25 deg C
    ! Ref:      Analogue function like 'calc_gstar_gepisat' in Python version
    !           and 'calc_vcmax25_colin' in R version (pmodel.R)
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: vcmax   ! Vcmax at a given temperature tc 
    real, intent(in) :: tc      ! air temperature (degrees C)

    ! loal variables
    real, parameter :: dhav = 65330    ! J/mol
    real, parameter :: kR   = 8.3145   ! J/mol/K

    real :: tk                         ! air temperature (Kelvin)

    ! function return variable
    real, intent(out) :: vcmax25  ! Vcmax at 25 deg C 

    !! conversion to temperature in Kelvin
    tk = tc + 273.15

    vcmax25 = vcmax * exp( -dhav/kR * (1/298.15 - 1/tk) )
    
  end function calc_vcmax25


  function calc_patm( elv ) result( patm )
    !-----------------------------------------------------------------------
    ! Features: Returns the atmospheric pressure as a function of elevation
    !           and standard atmosphere (1013.25 hPa)
    ! Depends:  - connect_sql
    !           - flux_to_grid
    !           - get_data_point
    !           - get_msvidx
    ! Ref:      Allen et al. (1998)
    !-----------------------------------------------------------------------
    ! argument
    real, intent(in) :: elv           ! elevation above sea level, m

    ! local variables
    real, parameter :: kPo = 101325   ! standard atmosphere, Pa (Allen, 1973)
    real, parameter :: kTo = 298.15   ! base temperature, K (Prentice, unpublished)
    real, parameter :: kL = 0.0065    ! temperature lapse rate, K/m (Allen, 1973)
    real, parameter :: kG = 9.80665   ! gravitational acceleration, m/s**2 (Allen, 1973)
    real, parameter :: kR = 8.3143    ! universal gas constant, J/mol/K (Allen, 1973)
    real, parameter :: kMa = 0.028963 ! molecular weight of dry air, kg/mol (Tsilingiris, 2008)

    ! function return variable
    real, intent(out) :: patm    ! atmospheric pressure at elevation 'elv', Pa 

    ! Convert elevation to pressure, Pa:
    patm = kPo*(1.0 - kL*elv/kTo)**(kG*kMa/(kR*kL))
    
  end function calc_patm


  function calc_density_h2o( tc, patm ) result( density_h2o )
    !-----------------------------------------------------------------------
    ! Features: Calculates density of water at a given temperature and 
    !           pressure using the Tumlirz Equation
    ! Ref:      F.H. Fisher and O.E Dial, Jr. (1975) Equation of state of 
    !           pure water and sea water, Tech. Rept., Marine Physical 
    !           Laboratory, San Diego, CA.
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: tc      ! air temperature (tc), degrees C
    real, intent(in) :: patm    ! atmospheric pressure (patm), Pa

    ! local variables
    real :: my_lambda, po, vinf, pbar, vau

    ! function return variable
    real, intent(out) :: density_h2o  ! density of water, kg/m**3

    ! Calculate lambda, (bar cm**3)/g:
    my_lambda = 1788.316 + &
            21.55053*tc + &
          -0.4695911*tc*tc + &
       (3.096363e-3)*tc*tc*tc + &
      -(7.341182e-6)*tc*tc*tc*tc

    ! Calculate po, bar
    po = 5918.499 + & 
             58.05267*tc + & 
           -1.1253317*tc*tc + & 
       (6.6123869e-3)*tc*tc*tc + & 
      -(1.4661625e-5)*tc*tc*tc*tc

    ! Calculate vinf, cm**3/g
    vinf = 0.6980547 + &
      -(7.435626e-4)*tc + &
       (3.704258e-5)*tc*tc + &
      -(6.315724e-7)*tc*tc*tc + &
       (9.829576e-9)*tc*tc*tc*tc + &
     -(1.197269e-10)*tc*tc*tc*tc*tc + &
      (1.005461e-12)*tc*tc*tc*tc*tc*tc + &
     -(5.437898e-15)*tc*tc*tc*tc*tc*tc*tc + &
       (1.69946e-17)*tc*tc*tc*tc*tc*tc*tc*tc + &
     -(2.295063e-20)*tc*tc*tc*tc*tc*tc*tc*tc*tc

    ! Convert pressure to bars (1 bar = 100000 Pa)
    pbar = (1e-5)*patm
    
    ! Calculate the specific volume (cm**3 g**-1):
    vau = vinf + my_lambda/(po + pbar)

    ! Convert to density (g cm**-3) -> 1000 g/kg; 1000000 cm**3/m**3 -> kg/m**3:
    density_h2o = (1e3/vau)

  end function calc_density_h2o


  function calc_viscosity_h2o( tc, patm ) result( viscosity_h2o )
    !-----------------------------------------------------------------------
    ! Features: Calculates viscosity of water at a given temperature and 
    !           pressure.
    ! Depends:  density_h2o
    ! Ref:      Huber, M. L., R. A. Perkins, A. Laesecke, D. G. Friend, J. V. 
    !           Sengers, M. J. Assael, ..., K. Miyagawa (2009) New 
    !           international formulation for the viscosity of H2O, J. Phys. 
    !           Chem. Ref. Data, Vol. 38(2), pp. 101-125.
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: tc      ! air temperature (tc), degrees C
    real, intent(in) :: patm    ! atmospheric pressure (patm), Pa

    ! local variables
    real, parameter :: tk_ast  = 647.096    ! Kelvin
    real, parameter :: rho_ast = 322.0      ! kg/m**3
    real, parameter :: mu_ast  = 1e-6       ! Pa s

    real, dimension(7,6) :: h_array
    real :: rho                             ! density of water kg/m**3
    real, tbar, tbarx, tbar2, tbar3, rbar, mu0, mu1, ctbar, mu_bar, &
      coef1, coef2
    integer :: i, j                         ! counter variables

    ! function return variable
    real :: viscosity_h2o

    ! Get the density of water, kg/m**3
    rho = calc_density_h2o(tc, patm)

    ! Calculate dimensionless parameters:
    tbar = (tc + 273.15)/tk_ast
    tbarx = tbar**(0.5)
    tbar2 = tbar**2
    tbar3 = tbar**3
    rbar = rho/rho_ast

    ! Calculate mu0 (Eq. 11 & Table 2, Huber et al., 2009):
    mu0 = 1.67752 + 2.20462/tbar + 0.6366564/tbar2 - 0.241605/tbar3
    mu0 = 1e2*tbarx/mu0

    ! Create Table 3, Huber et al. (2009):
    h_array(1,:) = (/0.520094, 0.0850895, -1.08374, -0.289555, 0.0, 0.0/)  ! hj0
    h_array(2,:) = (/0.222531, 0.999115, 1.88797, 1.26613, 0.0, 0.120573/) ! hj1
    h_array(3,:) = (/-0.281378, -0.906851, -0.772479, -0.489837, -0.257040, 0.0/) ! hj2
    h_array(4,:) = (/0.161913,  0.257399, 0.0, 0.0, 0.0, 0.0/) ! hj3
    h_array(5,:) = (/-0.0325372, 0.0, 0.0, 0.0698452, 0.0, 0.0/) ! hj4
    h_array(6,:) = (/0.0, 0.0, 0.0, 0.0, 0.00872102, 0.0/) ! hj5
    h_array(7,:) = (/0.0, 0.0, 0.0, -0.00435673, 0.0, -0.000593264/) ! hj6

    ! Calculate mu1 (Eq. 12 & Table 3, Huber et al., 2009):
    mu1 = 0.0
    ctbar = (1.0/tbar) - 1.0
    do i=1,6
      coef1 = ctbar**(i-1)
      coef2 = 0.0
      do j=1,7
        coef2 = coef2 + h_array(j,i) * (rbar - 1.0)**(j-1)
      end do
      mu1 = mu1 + coef1 * coef2    
    end do
    mu1 = exp( rbar * mu1 )

    ! Calculate mu_bar (Eq. 2, Huber et al., 2009)
    !   assumes mu2 = 1
    mu_bar = mu0 * mu1

    ! Calculate mu (Eq. 1, Huber et al., 2009)
    viscosity_h2o = mu_bar * mu_ast    ! Pa s

  end function calc_viscosity_h2o


  subroutine initdaily_gpp()
    !////////////////////////////////////////////////////////////////
    ! Initialise daily variables with zero
    !----------------------------------------------------------------
    dgpp(:)    = 0.0
    dtransp(:) = 0.0
    drd(:)     = 0.0

  end subroutine initdaily_gpp


  subroutine initio_gpp()
    !////////////////////////////////////////////////////////////////
    ! OPEN ASCII OUTPUT FILES FOR OUTPUT
    !----------------------------------------------------------------
    use _params_siml, only: runname, loutdgpp, loutdrd, loutdtransp

    ! local variables
    character(len=256) :: prefix
    character(len=256) :: filnam

    prefix = "./output/"//trim(runname)

    !----------------------------------------------------------------
    ! DAILY OUTPUT
    !----------------------------------------------------------------
    ! GPP
    if (loutdgpp) then
      filnam=trim(prefix)//'.d.gpp.out'
      open(101,file=filnam,err=888,status='unknown')
    end if 

    ! RD
    if (loutdrd) then
      filnam=trim(prefix)//'.d.rd.out'
      open(135,file=filnam,err=888,status='unknown')
    end if 

    ! TRANSPIRATION
    if (loutdtransp) then
      filnam=trim(prefix)//'.d.transp.out'
      open(114,file=filnam,err=888,status='unknown')
    end if

    !----------------------------------------------------------------
    ! MONTHLY OUTPUT
    !----------------------------------------------------------------
    ! GPP
    if (loutdgpp) then     ! monthly and daily output switch are identical
      filnam=trim(prefix)//'.m.gpp.out'
      open(151,file=filnam,err=888,status='unknown')
    end if 

    ! RD
    if (loutdrd) then     ! monthly and daily output switch are identical
      filnam=trim(prefix)//'.m.rd.out'
      open(152,file=filnam,err=888,status='unknown')
    end if 

    ! TRANSP
    if (loutdtransp) then     ! monthly and daily output switch are identical
      filnam=trim(prefix)//'.m.transp.out'
      open(153,file=filnam,err=888,status='unknown')
    end if 

    !----------------------------------------------------------------
    ! ANNUAL OUTPUT
    !----------------------------------------------------------------
    ! GPP 
    filnam=trim(prefix)//'.a.gpp.out'
    open(310,file=filnam,err=888,status='unknown')

    ! VCMAX (annual maximum) (mol m-2 s-1)
    filnam=trim(prefix)//'.a.vcmax.out'
    open(323,file=filnam,err=888,status='unknown')

    ! chi = ci:ca (annual mean, weighted by monthly PPFD) (unitless)
    filnam=trim(prefix)//'.a.chi.out'
    open(652,file=filnam,err=888,status='unknown')

    ! LUE (annual  mean, weighted by monthly PPFD) (unitless)
    filnam=trim(prefix)//'.a.lue.out'
    open(653,file=filnam,err=888,status='unknown')

    return

    888  stop 'INITIO_GPP: error opening output files'

  end subroutine initio_gpp


  subroutine initoutput_gpp()
    !////////////////////////////////////////////////////////////////
    !  Initialises waterbalance-specific output variables
    !----------------------------------------------------------------
    use _params_core, only: npft, ndayyear, nmonth, maxgrid
    use _params_siml, only: loutdgpp, loutdrd, loutdtransp

    ! daily
    if (loutdgpp      ) allocate( outdgpp      (npft,ndayyear,maxgrid) )
    if (loutdrd       ) allocate( outdrd       (npft,ndayyear,maxgrid) )
    if (loutdtransp   ) allocate( outdtransp   (npft,ndayyear,maxgrid) )
    outdgpp(:,:,:)    = 0.0
    outdrd(:,:,:)    = 0.0
    outdtransp(:,:,:) = 0.0

    ! monthly
    if (loutdgpp      ) allocate( outmgpp      (npft,nmonth,maxgrid) )
    if (loutdrd       ) allocate( outmrd       (npft,nmonth,maxgrid) )
    if (loutdtransp   ) allocate( outmtransp   (npft,nmonth,maxgrid) )
    outmgpp(:,:,:)    = 0.0
    outmrd(:,:,:)     = 0.0
    outmtransp(:,:,:) = 0.0

    ! annual
    outagpp(:,:)   = 0.0
    outavcmax(:,:) = 0.0
    outachi(:,:)   = 0.0
    outalue(:,:)   = 0.0

  end subroutine initoutput_gpp


  subroutine getout_daily_gpp( jpngr, moy, doy )
    !////////////////////////////////////////////////////////////////
    ! SR called daily to sum up daily output variables.
    ! Note that output variables are collected only for those variables
    ! that are global anyway (e.g., outdcex). Others are not made 
    ! global just for this, but are collected inside the subroutine 
    ! where they are defined.
    !----------------------------------------------------------------
    use _params_siml, only: loutdgpp, loutdrd, loutdtransp

    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: moy
    integer, intent(in) :: doy

    !----------------------------------------------------------------
    ! DAILY
    ! Collect daily output variables
    ! so far not implemented for isotopes
    !----------------------------------------------------------------
    if (loutdgpp      ) outdgpp(:,doy,jpngr)       = dgpp(:)
    if (loutdrd       ) outdrd(:,doy,jpngr)        = drd(:)
    if (loutdtransp   ) outdtransp(:,doy,jpngr)    = dtransp(:)

    !----------------------------------------------------------------
    ! MONTHLY SUM OVER DAILY VALUES
    ! Collect monthly output variables as sum of daily values
    !----------------------------------------------------------------
    if (loutdgpp      ) outmgpp(:,moy,jpngr)    = outmgpp(:,moy,jpngr) + dgpp(:)
    if (loutdrd       ) outmrd(:,moy,jpngr)     = outmrd(:,moy,jpngr)  + drd(:)
    if (loutdrd       ) outmtransp(:,moy,jpngr) = outmtransp(:,moy,jpngr)  + dtransp(:)

    !----------------------------------------------------------------
    ! ANNUAL SUM OVER DAILY VALUES
    ! Collect annual output variables as sum of daily values
    !----------------------------------------------------------------
    outagpp(:,jpngr) = outagpp(:,jpngr) + dgpp(:)

    ! store all daily values for outputting annual maximum
    outdvcmax_canop(:,doy) = vcmax_canop(:)


  end subroutine getout_daily_gpp


  subroutine getout_annual_gpp( jpngr )
    !////////////////////////////////////////////////////////////////
    !  SR called once a year to gather annual output variables.
    !----------------------------------------------------------------
    use _waterbal, only: solar

    ! arguments
    integer, intent(in) :: jpngr

    ! outanrlarea(jpngr) = anrlarea
    outavcmax(:,jpngr)   = avcmax(:)
    outachi(:,jpngr)     = sum( mchi(1,:) * solar%meanmppfd(:) ) / sum( solar%meanmppfd(:) )
    outalue(:,jpngr)     = sum( mlue(1,:) * solar%meanmppfd(:) ) / sum( solar%meanmppfd(:) )

  end subroutine getout_annual_gpp


  subroutine writeout_ascii_gpp( year, spinup )
    !/////////////////////////////////////////////////////////////////////////
    ! WRITE WATERBALANCE-SPECIFIC VARIABLES TO OUTPUT
    !-------------------------------------------------------------------------
    use _params_siml, only: outyear, loutdrd, loutdgpp, loutdtransp, daily_out_startyr, daily_out_endyr

    ! arguments
    integer, intent(in) :: year       ! simulation year
    logical, intent(in) :: spinup     ! true during spinup years

    ! local variables
    real :: itime
    integer :: day, moy, jpngr

    ! xxx implement this: sum over gridcells? single output per gridcell?
    if (maxgrid>1) stop 'writeout_ascii_gpp: think of something ...'
    jpngr = 1

    !-------------------------------------------------------------------------
    ! DAILY OUTPUT
    !-------------------------------------------------------------------------
    if ( .not. spinup .and. outyear>=daily_out_startyr .and. outyear<=daily_out_endyr ) then

      ! Write daily output only during transient simulation
      do day=1,ndayyear

        ! Define 'itime' as a decimal number corresponding to day in the year + year
        itime = real(outyear) + real(day-1)/real(ndayyear)

        if (loutdgpp   ) write(101,999) itime, sum(outdgpp(:,day,jpngr))
        if (loutdrd    ) write(135,999) itime, sum(outdrd(:,day,jpngr))
        if (loutdtransp) write(114,999) itime, sum(outdtransp(:,day,jpngr))

      end do

      do moy=1,nmonth

        ! Define 'itime' as a decimal number corresponding to day in the year + year
        itime = real(outyear) + real(moy-1)/real(nmonth)

        ! write(0,*) 'outmgpp ', outmgpp
        ! stop

        if (loutdgpp   ) write(151,999) itime, sum(outmgpp(:,moy,jpngr))
        if (loutdrd    ) write(152,999) itime, sum(outmrd (:,moy,jpngr))
        if (loutdtransp) write(153,999) itime, sum(outmtransp(:,moy,jpngr))

      end do

    end if

    !-------------------------------------------------------------------------
    ! ANNUAL OUTPUT
    ! Write annual value, summed over all PFTs / LUs
    ! xxx implement taking sum over PFTs (and gridcells) in this land use category
    !-------------------------------------------------------------------------
    itime = real(outyear)

    write(310,999) itime, sum(outagpp(:,jpngr))
    write(651,999) itime, sum(outavcmax(:,jpngr))
    write(652,999) itime, sum(outachi(:,jpngr))
    write(653,999) itime, sum(outalue(:,jpngr))

    return
    
    999 format (F20.8,F20.8)

  end subroutine writeout_ascii_gpp


  ! subroutine gettraits( jpngr )
  !   !//////////////////////////////////////////////////////////////////
  !   ! Calculates leaf traits at the beginning of the year based on 
  !   ! Vcmax25, assuming a constant ratio of leaf-C to leaf-structural N:
  !   ! - metabolic Narea
  !   ! - structural Narea
  !   ! - leaf C:N 
  !   ! - LMA, SLA
  !   !------------------------------------------------------------------
  !   use _params_modl, only: n_molmass, c_molmass, c_content_of_biomass
  !   use _vars_core, only: sla, lma, r_cton_leaf, r_ntoc_leaf
  !   use _waterbal, only: meanmppfd

  !   ! arguments
  !   integer, intent(in) :: jpngr 

  !   ! local variables
  !   integer :: pft, moy
  !   real    :: max_lai
  !   real    :: nr_leaf
  !   real    :: ncw_leaf
  !   real    :: cleaf

  !   ! xxx try: assumue seasonal maximum LAI to determine leaf N beforehand
  !   ! max_lai = 1.0

  !   ! write(0,*) 'meanmppfd', meanmppfd

  !   ! do moy=1,nmonth
  !   !   mvcmax(moy)   = calc_vcmax(    max_lai, mvcmax_unitiabs(moy), solar%meanmppfd(moy) )
  !   !   ! mnrlarea(moy) = calc_nr_leaf(  max_lai, mactnv_unitiabs(moy), solar%meanmppfd(moy) )
  !   ! end do
  !   ! avcmax = maxval( mvcmax(:) )
  !   ! anrlarea = maxval( mnrlarea(:) )

  !   ! write(0,*) 'mvcmax  ', mvcmax(:) * 1e3
  !   ! write(0,*) 'anrlarea', anrlarea
  !   ! stop

  !   ! do pft=1,npft

  !   !   ncw_leaf               = calc_ncw_leaf( anrlarea )
  !   !   cleaf                  = ncw_leaf * n_molmass * r_ctostructn_leaf
      
  !   !   r_cton_leaf(pft,jpngr) = cleaf / ( (anrlarea+ncw_leaf) * n_molmass )
  !   !   r_ntoc_leaf(pft,jpngr) = 1.0 / r_cton_leaf(pft,jpngr)
      
  !   !   lma(pft,jpngr)         = cleaf / c_content_of_biomass
  !   !   sla(pft,jpngr)         = 1.0 / lma(pft,jpngr)

  !   ! end do

  ! end subroutine gettraits


  ! function calc_nr_leaf( lai, mactnv_unitiabs, meanmppfd ) result( nr_leaf )
  !   !//////////////////////////////////////////////////////////////////
  !   ! Calculates leaf-level metabolic N content per unit leaf area as a
  !   ! function of Vcmax25.
  !   !------------------------------------------------------------------
  !   use _vegdynamics, only: get_fapar

  !   ! arguments
  !   real, intent(in) :: lai
  !   real, intent(in) :: mactnv_unitiabs
  !   real, intent(in) :: meanmppfd

  !   ! function return variable
  !   real, intent(out) :: nr_leaf

  !   ! local variables
  !   real :: fapar

  !   fapar = get_fapar( lai )

  !   ! Calculate leaf-scale Rubisco-N as a function of LAI and current LUE
  !   nr_leaf = fapar * meanmppfd * mactnv_unitiabs / lai

  ! end function calc_nr_leaf

  ! function calc_ncw_leaf( nr_leaf ) result( ncw_leaf )
  !   !//////////////////////////////////////////////////////////////////
  !   ! Calculates leaf-level structural N content per unit leaf area as a
  !   ! function of metabolic Narea.
  !   !------------------------------------------------------------------
  !   ! arguments
  !   real, intent(in) :: nr_leaf

  !   ! function return variable
  !   real, intent(out) :: ncw_leaf

  !   ncw_leaf = nr_leaf * r_n_cw_v + ncw_min

  ! end function calc_ncw_leaf
  

  ! function calc_n_rubisco_area( vcmax25 ) result( n_rubisco_area )
  !   !-----------------------------------------------------------------------
  !   ! Returns Rubisco N content per unit leaf area for a given Vcmax.
  !   ! Reference: Harrison et al., 2009, Plant, Cell and Environment; Eq. 3
  !   !-----------------------------------------------------------------------

  !   ! argument
  !   real, intent(in) :: vcmax25                      ! leaf level Vcmax  at 25 deg C, (mol CO2) m-2 s-1

  !   ! function retrurn value
  !   real, intent(out) :: n_rubisco_area              ! Rubisco N content per unit leaf area, (g N)(m-2 leaf)

  !   ! local variables
  !   real :: n_v                                      ! Rubisco N per unit Vcmax (xxx units xxx)

  !   real, parameter :: mol_weight_rubisco = 5.5e5    ! molecular weight of Rubisco, (g R)(mol R)-1
  !   real, parameter :: n_conc_rubisco     = 1.14e-2  ! N concentration in rubisco, (mol N)(g R)-1
  !   real, parameter :: n_molmass       = 14.0067  ! molecular weight of N, (g N)(mol N)-1
  !   real, parameter :: cat_turnover_per_site = 3.5   ! catalytic turnover rate per site at 25 deg C, (mol CO2)(mol R sites)-1
  !   real, parameter :: cat_sites_per_mol_R   = 8.0   ! number of catalytic sites per mol R, (mol R sites)(mol R)-1

  !   ! Metabolic N ratio
  !   n_v = mol_weight_rubisco * n_conc_rubisco * n_molmass / ( cat_turnover_per_site * cat_sites_per_mol_R )

  !   n_rubisco_area = vcmax25 * n_v

  ! end function calc_n_rubisco_area


end module _gpp