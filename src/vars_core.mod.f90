module md_vars_core
  !////////////////////////////////////////////////////////////////




  !  XXX DISCONTINUED XXX






  
  ! MANDATORY (MODULE-INDEPENDENT) VARIABLES
  ! *not* output variables.
  ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
  ! contact: b.stocker@imperial.ac.uk
  !----------------------------------------------------------------
  use md_params_core
  use md_classdefs

  implicit none

  !////////////////////////////////////////////////////////////////
  ! FLUXES
  ! Daily updated model state variables (no dimension for days). 
  ! These variables have no spatial dimension, no information is 
  ! carried over between years, but are re-calculated daily. 
  ! At the end of the daily loop, values may be copied to output 
  ! variables that contain a spatial and a day dimension.
  ! All these variables are required by the model and are independent
  ! of which modules are used.
  !----------------------------------------------------------------
  type(carbon), dimension(nlu)    :: dnep     ! net ecosystem production [gC/m2/d]
  type(carbon), dimension(npft)   :: dnpp     ! net primary production [gC/m2/d]

  type(carbon), dimension(npft)   :: drsoil   ! soil respiration (only from exudates decomp.) [gC/m2/d]
  type(carbon), dimension(nlu)    :: drhet    ! heterotrophic respiration [gC/m2/d]
  real, dimension(npft)           :: drauto   ! autotrophic respiration (growth+maintenance resp. of all compartments), no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)           :: drleaf   ! leaf maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)           :: drroot   ! root maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)           :: drsapw   ! sapwood maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)           :: drgrow   ! growth respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)           :: dcex     ! labile C exudation for N uptake, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]

  real, dimension(nlu)            :: doc      ! daily soil turnover, used as surrogate for labile C (former 'doc') [gC/m2/d]

  type(nitrogen), dimension(npft) :: dnup     ! daily N uptake [gN/m2/d]

                                 ! variables without spatial dimension: have NO memory from one to next year
  type(orgpool), dimension(nlu)   :: aestab   ! annual C and N fixation due to establishment (=acflux_estab,an_uptake_estab)


  !////////////////////////////////////////////////////////////////
  ! POOLS
  ! Variables contain a spatial dimension (of lenth maxgrid), to 
  ! carry over information between years (pool size has memory from
  ! one year to the next). 
  ! Daily output for pool variables is done by copying value of pool 
  ! to the respective output variable that contains a dimension for 
  ! days. Always use 'p' as a prefix of variable name.
  ! All these variables are required by the model and are independent
  ! of which modules are used.
  !----------------------------------------------------------------
  type(orgpool), dimension(npft,maxgrid) :: pleaf           ! leaf biomass [gC/ind.] (=lm_ind)
  type(orgpool), dimension(npft,maxgrid) :: proot           ! root biomass [gC/ind.] (=rm_ind)
  type(orgpool), dimension(npft,maxgrid) :: psapw           ! sapwood biomass [gC/ind.] (=sm_ind)
  type(orgpool), dimension(npft,maxgrid) :: pwood           ! heartwood (non-living) biomass [gC/ind.] (=hm_ind)
  type(orgpool), dimension(npft,maxgrid) :: plabl           ! labile pool, temporary storage of N and C [gC/ind.] (=bm_inc but contains also N) 
  
  type(carbon),  dimension(npft,maxgrid) :: pexud           ! exudates pool (very short turnover) [gC/m2]
  
  type(orgpool), dimension(npft,maxgrid) :: plitt_af        ! above-ground litter, fast turnover [gC/m2]
  type(orgpool), dimension(npft,maxgrid) :: plitt_as        ! above-ground litter, slow turnover [gC/m2]
  type(orgpool), dimension(npft,maxgrid) :: plitt_bg        ! below-ground litter [gC/m2]
  
  type(orgpool), dimension(nlu,maxgrid)  :: psoil_sl        ! soil organic matter, fast turnover [gC/m2]
  type(orgpool), dimension(nlu,maxgrid)  :: psoil_fs        ! soil organic matter, slow turnover [gC/m2]
  
  type(nitrogen), dimension(nlu,maxgrid) :: pninorg         ! total inorganic N pool (sum of NO3 and NH4) [gC/m2]
    
  ! xxx todo: do we really need maxgrid dimension for these variables?
  real, dimension(npft,maxgrid)          :: r_cton_leaf     ! leaf C:N ratio [gC/gN] 
  real, dimension(npft,maxgrid)          :: r_ntoc_leaf     ! leaf N:C ratio [gN/gC]
  real, dimension(npft,maxgrid)          :: lma, sla        ! leaf mass per area [gC/m2], specific leaf area [m2/gC]. C, NOT DRY-MASS!
  real, dimension(npft)                  :: narea           ! g N m-2-leaf
  real, dimension(npft)                  :: narea_metabolic ! g N m-2-leaf
  real, dimension(npft)                  :: narea_structural! g N m-2-leaf
  real, dimension(npft)                  :: nmass           ! g N / g-dry mass

  real, dimension(npft,maxgrid)          :: lai_ind
  real, dimension(npft,maxgrid)          :: fapar_ind


  !////////////////////////////////////////////////////////////////
  ! OTHER STATE VARIABLES
  !----------------------------------------------------------------
  logical, dimension(npft,maxgrid) :: ispresent   ! boolean whether PFT is present
  real, dimension(npft,maxgrid)    :: fpc_grid    ! area fraction within gridcell occupied by PFT
  real, dimension(npft,maxgrid)    :: nind        ! number of individuals [1/m2]

  real, dimension(npft,maxgrid)    :: height      ! tree height (m)
  real, dimension(npft,maxgrid)    :: crownarea   ! individual's tree crown area

  real, dimension(nlu)             :: ddoc            ! surrogate for dissolved organic carbon


contains

  subroutine initglobal()
    !////////////////////////////////////////////////////////////////
    !  Initialisation of all _pools on all gridcells at the beginning
    !  of the simulation.
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    use md_classdefs
    use md_params_modl, only: params_pft
    use md_params_core, only: npft, maxgrid

    ! local variables
    integer :: pft
    integer :: jpngr

    !-----------------------------------------------------------------------------
    ! derive which PFTs are present from fpc_grid (which is prescribed)
    !-----------------------------------------------------------------------------
    do jpngr=1,maxgrid
      do pft=1,npft
        if (fpc_grid(pft,jpngr)>0.0) then
          ispresent(pft,jpngr) = .true.
        else
          ispresent(pft,jpngr) = .false.
        end if
      end do
    end do
 

    ! initialise all _pools with zero
    pleaf(:,:)    = orgpool(carbon(0.0),nitrogen(0.0))    ! leaves   , organic pool [gC/m2/ind. and gN/m2/ind.]
    proot(:,:)    = orgpool(carbon(0.0),nitrogen(0.0))    ! roots    , organic pool [gC/m2/ind. and gN/m2/ind.]
    psapw(:,:)    = orgpool(carbon(0.0),nitrogen(0.0))    ! sapwood  , organic pool [gC/m2/ind. and gN/m2/ind.]
    pwood(:,:)    = orgpool(carbon(0.0),nitrogen(0.0))    ! heartwood, organic pool [gC/m2/ind. and gN/m2/ind.]
    plabl(:,:)    = orgpool(carbon(0.0),nitrogen(0.0))    ! labile   , organic pool [gC/m2/ind. and gN/m2/ind.]

    pexud(:,:)    = carbon(0.0)                           ! exudates in soil, carbon pool [gC/m2]

    plitt_af(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! above-ground fine   litter, organic pool [gC/m2 and gN/m2]
    plitt_as(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! above-ground coarse litter, organic pool [gC/m2 and gN/m2]
    plitt_bg(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! below-ground fine   litter, organic pool [gC/m2 and gN/m2]

    psoil_sl(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! fast decomposing soil organic matter, organic pool [gC/m2 and gN/m2]
    psoil_fs(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! recalcitrant soil organic matter    , organic pool [gC/m2 and gN/m2]

    !! xxx try
    !! initialise _pools with non-zero values
    !! here example gridcell 9.5 E, 47.5 N
    ! psoil_fs(:,:) = orgpool( carbon(4000.0), nitrogen(150.0) )
    ! psoil_sl(:,:) = orgpool( carbon(10000.0), nitrogen(550.0) )
    
    ! xxx debug: change back to 0.0
    pninorg(:,:)  = nitrogen(10.0)

    ! initialise other properties
    lai_ind(:,:)   = 0.0
    fapar_ind(:,:)   = 0.0
    height(:,:)    = 0.0

    do pft=1,npft
      if (params_pft%tree(pft)) then
        nind(pft,:)      = 0.0
        crownarea(pft,:) = 0.0
      else
        nind(pft,:)      = 1.0
        crownarea(pft,:) = 1.0
      end if
    end do

    lma(:,:) = 0.0
    sla(:,:) = 0.0

  end subroutine initglobal


  subroutine initpft( pft, jpngr )
    !////////////////////////////////////////////////////////////////
    !  Initialisation of specified PFT on specified gridcell
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    use md_classdefs
    use md_params_modl, only: params_pft

    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! initialise all _pools with zero
    pleaf(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    proot(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    plabl(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    if (params_pft%tree(pft)) then
      psapw(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
      pwood(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    endif

    ! initialise other properties
    fpc_grid(pft,jpngr)  = 0.0
    lai_ind(pft,jpngr)   = 0.0
    fapar_ind(pft,jpngr)   = 0.0
    height(pft,jpngr)    = 0.0
    if (params_pft%tree(pft)) then
      nind(pft,jpngr)      = 0.0
      crownarea(pft,jpngr) = 0.0
    else
      nind(pft,jpngr)      = 1.0
      crownarea(pft,jpngr) = 1.0
    endif

    !if (.not.grass(pft)) then
    !sm_ind(pft,jpngr,1)=orgpool(carbon(0.0),nitrogen(0.0))
    !hm_ind(pft,jpngr,1)=orgpool(carbon(0.0),nitrogen(0.0))
    ! end if

    ! xxx put this somewhere else
    !if(.not.tree(pft)) crownarea(pft,jpngr)=1.0d0
    !leafon(pft,jpngr)=.true.
    !leafondays(pft,jpngr)=0.0d0
    !leafoffdays(pft,jpngr)=0.0d0


  end subroutine initpft


  subroutine initannual()
    !////////////////////////////////////////////////////////////////
    !  Initialises all annually updated variables with zero.
    !----------------------------------------------------------------
    use md_classdefs

    aestab(:) = orgpool(carbon(0.0),nitrogen(0.0))

  end subroutine initannual


  subroutine initdaily
    !////////////////////////////////////////////////////////////////
    ! Initialises all daily variables with zero.
    !----------------------------------------------------------------
    use md_classdefs

    dnpp(:)        = carbon(0.0)
    drsoil(:)      = carbon(0.0)
    drhet(:)       = carbon(0.0)
    dnep(:)        = carbon(0.0)
    dcex(:)        = 0.0
    drauto(:)      = 0.0
    drleaf(:)      = 0.0
    drroot(:)      = 0.0
    drgrow(:)      = 0.0
    dnup(:)        = nitrogen(0.0)
    ddoc(:)        = 0.0

    !! xxx try
    !! hold soil carbon and litter _pools at a constant size
    !! here example gridcell 9.5 E, 47.5 N
    !psoil_fs = orgpool( carbon(4000.0), nitrogen(150.0) )
    !psoil_sl = orgpool( carbon(10000.0), nitrogen(550.0) )

    !plitt_af = orgpool( carbon(500.0), nitrogen(10.0))
    !plitt_as = orgpool( carbon(1500.0), nitrogen(30.0))
    !plitt_bg = orgpool( carbon(400.0), nitrogen(8.))

    ! ! xxx try: 
    ! pninorg%n14 = 0.05

  end subroutine initdaily


end module md_vars_core
