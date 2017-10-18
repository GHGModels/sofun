module md_interface

  use md_params_core, only: maxgrid, nlu, ndayyear, dummy
  use md_grid, only: gridtype, domaininfo_type
  use md_forcing, only: landuse_type, climate_type, ninput_type
  use md_params_domain, only: type_params_domain
  use md_params_soil, only: paramtype_soil
  use md_params_siml, only: outtype_steering, paramstype_siml

  implicit none

  private
  public interfacetype_biosphere, interface, initoutput_forcing, initio_forcing, &
    initio_nc_forcing, getout_daily_forcing, writeout_ascii_forcing, writeout_nc_forcing

  type interfacetype_biosphere
    integer                                             :: year
    real                                                :: pco2
    type( gridtype )      , dimension(:),   allocatable :: grid
    type( paramtype_soil ), dimension(:),   allocatable :: soilparams
    type( landuse_type)   , dimension(:),   allocatable :: landuse
    type( climate_type )  , dimension(:),   allocatable :: climate
    type( ninput_type)    , dimension(:),   allocatable :: ninput_field
    real                  , dimension(:,:), allocatable :: dfapar_field
    type( domaininfo_type )                             :: domaininfo
    type( outtype_steering )                            :: steering
    type( paramstype_siml )                             :: params_siml
  end type interfacetype_biosphere

  !----------------------------------------------------------------
  ! Interface instance is created here 
  ! (instead of locally defined and passed on as argument. Both are 
  ! ok but this has the advantage that unknown-size arguments are
  ! avoided).
  !----------------------------------------------------------------
  type( interfacetype_biosphere ) :: interface

  !----------------------------------------------------------------
  ! Module-specific daily output variables
  !----------------------------------------------------------------
  real, allocatable, dimension(:,:) :: outdtemp
  real, allocatable, dimension(:,:) :: outdfapar

  !----------------------------------------------------------------
  ! Module-specific NetCDF output file and variable names
  !----------------------------------------------------------------
  character(len=256) :: ncoutfilnam_temp
  character(len=256) :: ncoutfilnam_fapar

  character(len=*), parameter :: TEMP_NAME="temp"
  character(len=*), parameter :: FAPAR_NAME="fapar"

  ! !----------------------------------------------------------------
  ! ! Module-specific annual output variables
  ! !----------------------------------------------------------------
  ! real, dimension(maxgrid)     :: outatemp
  ! real, dimension(nlu,maxgrid) :: outanin


contains

  subroutine initoutput_forcing( ngridcells )
    !////////////////////////////////////////////////////////////////
    ! Initialises all daily variables with zero.
    ! Called at the beginning of each year by 'biosphere'.
    !----------------------------------------------------------------
    use md_params_core, only: ndayyear

    ! arguments
    integer, intent(in) :: ngridcells

    ! Allocate memory for daily output variables
    if ( interface%steering%init .and. interface%params_siml%loutdtemp  ) allocate( outdtemp (ndayyear,ngridcells) )
    if ( interface%steering%init .and. interface%params_siml%loutdfapar ) allocate( outdfapar(ndayyear,ngridcells) )

    if ( interface%params_siml%loutdtemp  ) outdtemp (:,:) = 0.0
    if ( interface%params_siml%loutdfapar ) outdfapar(:,:) = 0.0

  end subroutine initoutput_forcing


  subroutine initio_forcing()
    !////////////////////////////////////////////////////////////////
    ! Opens ascii output files.
    !----------------------------------------------------------------
    ! local variables
    character(len=256) :: prefix
    character(len=256) :: filnam

    prefix = "./output/"//trim(interface%params_siml%runname)

    !////////////////////////////////////////////////////////////////
    ! DAILY OUTPUT: OPEN ASCII OUTPUT FILES 
    !----------------------------------------------------------------
    ! DAILY MEAN TEMPERATURE (DEG C)
    if (interface%params_siml%loutdtemp) then
      filnam=trim(prefix)//'.d.temp.out'
      open(950,file=filnam,err=999,status='unknown')
    end if 

    ! FRACTION OF ABSORBED PHOTOSYNTHETICALLY ACTIVE RADIATION
    if (interface%params_siml%loutdfapar) then
      filnam=trim(prefix)//'.d.fapar.out'
      open(951,file=filnam,err=999,status='unknown')
    end if     

    return

    999  stop 'INITIO: error opening output files'

  end subroutine initio_forcing


  subroutine initio_nc_forcing()
    !////////////////////////////////////////////////////////////////
    ! Opens NetCDF output files.
    !----------------------------------------------------------------
    use netcdf
    use md_io_netcdf, only: init_nc_3D, check

    ! local variables
    character(len=256) :: prefix

    character(len=*), parameter :: DOY_NAME  = "doy"
    character(len=*), parameter :: YEAR_NAME = "year"
    character(len=*), parameter :: title     = "SOFUN GP-model output, module md_interface"
    character(len=4) :: year_char

    integer :: jpngr, doy
    integer, dimension(ndayyear) :: doy_vals

    write(year_char,999) interface%steering%outyear

    doy_vals = (/ (doy, doy = 1, ndayyear) /)

    if (interface%params_siml%lncoutdtemp) then

      prefix = "./output_nc/"//trim(interface%params_siml%runname)

      ! Create the netCDF file. The nf90_clobber parameter tells netCDF to
      ! overwrite this file, if it already exists.
      print*,'initialising temp NetCDF file ...'
      ncoutfilnam_temp = trim(prefix)//'.'//year_char//".d.temp.nc"
      call init_nc_3D( filnam  = ncoutfilnam_temp, &
                      nlon     = interface%domaininfo%nlon, &
                      nlat     = interface%domaininfo%nlat, &
                      nz       = ndayyear, &
                      lon      = interface%domaininfo%lon, &
                      lat      = interface%domaininfo%lat, &
                      zvals    = doy_vals, &
                      recvals  = interface%steering%outyear, &
                      znam     = DOY_NAME, &
                      recnam   = YEAR_NAME, &
                      varnam   = TEMP_NAME, &
                      varunits = "degrees Celsius", &
                      longnam  = "daily average 2 m temperature", &
                      title    = title &
                      )

    end if

    if (interface%params_siml%lncoutdfapar) then

      prefix = "./output_nc/"//trim(interface%params_siml%runname)

      ! Create the netCDF file. The nf90_clobber parameter tells netCDF to
      ! overwrite this file, if it already exists.
      print*,'initialising fapar NetCDF file ...'
      ncoutfilnam_fapar = trim(prefix)//'.'//year_char//".d.fapar.nc"
      call init_nc_3D( filnam  = ncoutfilnam_fapar, &
                      nlon     = interface%domaininfo%nlon, &
                      nlat     = interface%domaininfo%nlat, &
                      nz       = ndayyear, &
                      lon      = interface%domaininfo%lon, &
                      lat      = interface%domaininfo%lat, &
                      zvals    = doy_vals, &
                      recvals  = interface%steering%outyear, &
                      znam     = DOY_NAME, &
                      recnam   = YEAR_NAME, &
                      varnam   = FAPAR_NAME, &
                      varunits = "unitless", &
                      longnam  = "fraction of absorbed photosynthetically active radiation", &
                      title    = title &
                      )

    end if

    999  format (I4.4)

  end subroutine initio_nc_forcing


  subroutine getout_daily_forcing( jpngr, moy, doy )
    !////////////////////////////////////////////////////////////////
    ! SR called daily to sum up daily output variables.
    ! Note that output variables are collected only for those variables
    ! that are global anyway (e.g., outdcex). Others are not made 
    ! global just for this, but are collected inside the subroutine 
    ! where they are defined.
    !----------------------------------------------------------------
    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: moy
    integer, intent(in) :: doy

    !----------------------------------------------------------------
    ! DAILY
    ! Collect daily output variables
    ! so far not implemented for isotopes
    !----------------------------------------------------------------
    if (interface%params_siml%loutdtemp ) outdtemp (doy,jpngr) = interface%climate(jpngr)%dtemp (doy)
    if (interface%params_siml%loutdfapar) outdfapar(doy,jpngr) = interface%dfapar_field(doy,jpngr)

    ! !----------------------------------------------------------------
    ! ! ANNUAL SUM OVER DAILY VALUES
    ! ! Collect annual output variables as sum of daily values
    ! !----------------------------------------------------------------
    ! if (interface%params_siml%loutforcing) then
    !   outatemp(jpngr)  = outatemp(jpngr)  + interface%climate(jpngr)%dtemp(doy) / ndayyear
    !   outanin(:,jpngr) = outanin(:,jpngr) + interface%ninput_field(jpngr)%dtot(doy)
    ! end if

  end subroutine getout_daily_forcing


  subroutine writeout_ascii_forcing()
    !/////////////////////////////////////////////////////////////////////////
    ! Write daily ASCII output
    !-------------------------------------------------------------------------
    ! use md_params_siml, only: spinup, interface%params_siml%daily_out_startyr, &
    use md_params_core, only: ndayyear

    ! local variables
    real :: itime
    integer :: doy, moy, jpngr
    real, dimension(ndayyear) :: outdtemp_tot
    real, dimension(ndayyear) :: outdfapar_tot

    outdtemp_tot(:)  = 0.0
    outdfapar_tot(:) = 0.0

    if (nlu>1) stop 'Output only for one LU category implemented.'

    !-------------------------------------------------------------------------
    ! DAILY OUTPUT
    ! Write daily value, summed over all PFTs / LUs
    ! xxx implement taking sum over PFTs (and gridcells) in this land use category
    !-------------------------------------------------------------------------
    ! if ( .not. interface%steering%spinup &
    !   .and. interface%steering%outyear>=interface%params_siml%daily_out_startyr &
    !   .and. interface%steering%outyear<=interface%params_siml%daily_out_endyr ) then

      ! Write daily output only during transient simulation
      do doy=1,ndayyear

        ! Get weighted average
        do jpngr=1,size(interface%grid)
          if (interface%params_siml%loutdtemp ) outdtemp_tot(doy)  = outdtemp_tot(doy)  + outdtemp(doy,jpngr)  * interface%grid(jpngr)%landfrac * interface%grid(jpngr)%area
          if (interface%params_siml%loutdfapar) outdfapar_tot(doy) = outdfapar_tot(doy) + outdfapar(doy,jpngr) * interface%grid(jpngr)%landfrac * interface%grid(jpngr)%area
        end do
        if (interface%params_siml%loutdtemp ) outdtemp_tot(doy)  = outdtemp_tot(doy)  / interface%domaininfo%landarea
        if (interface%params_siml%loutdfapar) outdfapar_tot(doy) = outdfapar_tot(doy) / interface%domaininfo%landarea

        ! Define 'itime' as a decimal number corresponding to day in the year + year
        itime = real( interface%steering%outyear ) + real( doy - 1 ) / real( ndayyear )
        
        if (interface%params_siml%loutdtemp)  write(950,999) itime, outdtemp_tot(doy)
        if (interface%params_siml%loutdfapar) write(951,999) itime, outdfapar_tot(doy)

      end do
    ! end if

    return

    999 format (F20.8,F20.8)

  end subroutine writeout_ascii_forcing


  subroutine writeout_nc_forcing()
    !/////////////////////////////////////////////////////////////////////////
    ! Write NetCDF output
    !-------------------------------------------------------------------------
    use netcdf
    use md_io_netcdf, only: write_nc_3D, check

    ! local variables
    integer :: doy, jpngr
    integer :: ncid
    integer :: varid_temp

    real, dimension(:,:,:,:), allocatable :: outarr

    ! if ( .not. interface%steering%spinup &
    !       .and. interface%steering%outyear>=interface%params_siml%daily_out_startyr &
    !       .and. interface%steering%outyear<=interface%params_siml%daily_out_endyr ) then

      !-------------------------------------------------------------------------
      ! dtemp
      !-------------------------------------------------------------------------
      print*,'writing temp NetCDF file ...'
      if (interface%params_siml%lncoutdtemp) call write_nc_3D(  ncoutfilnam_temp, &
                                                                TEMP_NAME, &
                                                                interface%domaininfo%maxgrid, &
                                                                interface%domaininfo%nlon, &
                                                                interface%domaininfo%nlat, &
                                                                interface%grid(:)%ilon, &
                                                                interface%grid(:)%ilat, &
                                                                ndayyear, &
                                                                outdtemp(:,:) &
                                                                )


      !-------------------------------------------------------------------------
      ! fapar
      !-------------------------------------------------------------------------
      print*,'writing fapar NetCDF file ...'
      if (interface%params_siml%lncoutdfapar) call write_nc_3D( ncoutfilnam_fapar, &
                                                                FAPAR_NAME, &
                                                                interface%domaininfo%maxgrid, &
                                                                interface%domaininfo%nlon, &
                                                                interface%domaininfo%nlat, &
                                                                interface%grid(:)%ilon, &
                                                                interface%grid(:)%ilat, &
                                                                ndayyear, &
                                                                outdfapar(:,:) &
                                                                )

  end subroutine writeout_nc_forcing

end module md_interface
