module CNFireNoFireMod

#include "shr_assert.h"

  !-----------------------------------------------------------------------
  ! !DESCRIPTION:
  ! module for fire dynamics with fire explicitly turned off
  !
  ! !USES:
  use shr_kind_mod                       , only : r8 => shr_kind_r8
  use abortutils                         , only : endrun
  use clm_varctl                         , only : iulog
  use decompMod                          , only : bounds_type
  use atm2lndType                        , only : atm2lnd_type
  use CNVegStateType                     , only : cnveg_state_type
  use CNVegCarbonStateType               , only : cnveg_carbonstate_type
  use CNVegCarbonFluxType                , only : cnveg_carbonflux_type
  use CNVegNitrogenStateType             , only : cnveg_nitrogenstate_type
  use CNVegNitrogenFluxType              , only : cnveg_nitrogenflux_type
  use EnergyFluxType                     , only : energyflux_type
  use SaturatedExcessRunoffMod           , only : saturated_excess_runoff_type
  use WaterDiagnosticBulkType            , only : waterdiagnosticbulk_type
  use Wateratm2lndBulkType               , only : wateratm2lndbulk_type
  use WaterStateBulkType                 , only : waterstatebulk_type
  use SoilStateType                      , only : soilstate_type
  use SoilWaterRetentionCurveMod         , only : soil_water_retention_curve_type
  use FireMethodType                     , only : fire_method_type
  use CNFireBaseMod                      , only : cnfire_base_type
  !
  implicit none
  private
  !
  ! !PUBLIC TYPES:
  public :: cnfire_nofire_type
  !
  type, extends(cnfire_base_type) :: cnfire_nofire_type
    private
  contains
    !
    ! !PUBLIC MEMBER FUNCTIONS:
    procedure, public :: need_lightning_and_popdens  ! If need lightning and/or population density (always .false. here)
    procedure, public :: NoFireInit                  ! Initiialization
    procedure, public :: FireInit => NoFireInit      ! Initiialization
    procedure, public :: CNFireArea                  ! Calculate fire area
  end type cnfire_nofire_type

  character(len=*), parameter, private :: sourcefile = &
  __FILE__

contains

  !-----------------------------------------------------------------------
  function need_lightning_and_popdens(this)
    ! !ARGUMENTS:
    class(cnfire_nofire_type), intent(in) :: this
    logical :: need_lightning_and_popdens  ! function result
    !
    ! !LOCAL VARIABLES:

    character(len=*), parameter :: subname = 'need_lightning_and_popdens'
    !-----------------------------------------------------------------------

    need_lightning_and_popdens = .false.
  end function need_lightning_and_popdens

  !-----------------------------------------------------------------------
  subroutine NoFireInit( this, bounds )
    !
    ! !DESCRIPTION:
    ! Initialize No Fire module
    use shr_fire_emis_mod, only : shr_fire_emis_mechcomps_n
    use shr_log_mod      , only : errMsg => shr_log_errMsg
    ! !ARGUMENTS:
    class(cnfire_nofire_type) :: this
    type(bounds_type), intent(in) :: bounds

    if ( shr_fire_emis_mechcomps_n > 0) then
      write(iulog,*) "Fire emissions can NOT be active for fire_method=nofire" // &
                  errMsg(sourcefile, __LINE__)
      call endrun(msg="Having fire emissions on requires fire_method to be something besides nofire" )
      return
    end if
    call this%CNFireInit( bounds )

  end subroutine NoFireInit
  !-----------------------------------------------------------------------

  !-----------------------------------------------------------------------
  subroutine CNFireArea (this, bounds, num_soilc, filter_soilc, num_soilp, filter_soilp, &
       num_exposedvegp, filter_exposedvegp, num_noexposedvegp, filter_noexposedvegp, &
       atm2lnd_inst, energyflux_inst, saturated_excess_runoff_inst, &
       waterdiagnosticbulk_inst, wateratm2lndbulk_inst, &
       waterstatebulk_inst, soilstate_inst, soil_water_retention_curve, &
       crop_inst, cnveg_state_inst, cnveg_carbonstate_inst, totlitc_col, decomp_cpools_vr_col, t_soi17cm_col)
    !
    ! !DESCRIPTION:
    ! Computes column-level burned area 
    !
    ! !USES:
    use subgridAveMod                      , only : p2c
    use CropType                           , only : crop_type
    !
    ! !ARGUMENTS:
    class(cnfire_nofire_type)                             :: this
    type(bounds_type)                     , intent(in)    :: bounds 
    integer                               , intent(in)    :: num_soilc       ! number of soil columns in filter
    integer                               , intent(in)    :: filter_soilc(:) ! filter for soil columns
    integer                               , intent(in)    :: num_soilp       ! number of soil patches in filter
    integer                               , intent(in)    :: filter_soilp(:) ! filter for soil patches
    integer                               , intent(in)    :: num_exposedvegp        ! number of points in filter_exposedvegp
    integer                               , intent(in)    :: filter_exposedvegp(:)  ! patch filter for non-snow-covered veg
    integer                               , intent(in)    :: num_noexposedvegp       ! number of points in filter_noexposedvegp
    integer                               , intent(in)    :: filter_noexposedvegp(:) ! patch filter where frac_veg_nosno is 0
    type(atm2lnd_type)                    , intent(in)    :: atm2lnd_inst
    type(energyflux_type)                 , intent(in)    :: energyflux_inst
    type(saturated_excess_runoff_type)    , intent(in)    :: saturated_excess_runoff_inst
    type(waterdiagnosticbulk_type)        , intent(in)    :: waterdiagnosticbulk_inst
    type(wateratm2lndbulk_type)           , intent(in)    :: wateratm2lndbulk_inst
    type(waterstatebulk_type)             , intent(in)    :: waterstatebulk_inst
    type(soilstate_type)                  , intent(in)    :: soilstate_inst
    class(soil_water_retention_curve_type), intent(in)    :: soil_water_retention_curve
    type(cnveg_state_type)                , intent(inout) :: cnveg_state_inst
    type(cnveg_carbonstate_type)          , intent(inout) :: cnveg_carbonstate_inst
    type(crop_type)                       , intent(in)    :: crop_inst
    real(r8)                              , intent(in)    :: totlitc_col(bounds%begc:)
    real(r8)                              , intent(in)    :: decomp_cpools_vr_col(bounds%begc:,1:,1:)
    real(r8)                              , intent(in)    :: t_soi17cm_col(bounds%begc:)
    !
    ! !LOCAL VARIABLES:
    integer  :: c,fc   ! index variables
    !-----------------------------------------------------------------------

    associate(                                                                      & 
         cropf_col          => cnveg_state_inst%cropf_col                      , & ! Input:  [real(r8) (:)     ]  cropland fraction in veg column                   
         baf_crop           => cnveg_state_inst%baf_crop_col                   , & ! Output: [real(r8) (:)     ]  burned area fraction for cropland (/sec)  
         baf_peatf          => cnveg_state_inst%baf_peatf_col                  , & ! Output: [real(r8) (:)     ]  burned area fraction for peatland (/sec)  
         fbac               => cnveg_state_inst%fbac_col                       , & ! Output: [real(r8) (:)     ]  total burned area out of conversion (/sec)
         fbac1              => cnveg_state_inst%fbac1_col                      , & ! Output: [real(r8) (:)     ]  burned area out of conversion region due to land use fire
         lfc                => cnveg_state_inst%lfc_col                        , & ! Output: [real(r8) (:)     ]  conversion area frac. of BET+BDT that haven't burned before
         leafc              => cnveg_carbonstate_inst%leafc_patch              , & ! Input:  [real(r8) (:)     ]  (gC/m2) leaf C                                    
         leafc_col          => cnveg_carbonstate_inst%leafc_col                , & ! Output: [real(r8) (:)     ]  leaf carbon at column level 
         farea_burned       => cnveg_state_inst%farea_burned_col                 & ! Output: [real(r8) (:)     ]  total fractional area burned (/sec)
         )
 
      !pft to column average 
      call p2c(bounds, num_soilc, filter_soilc, &
           leafc(bounds%begp:bounds%endp), &
           leafc_col(bounds%begc:bounds%endc))
     !
     ! begin column loop to calculate fractional area affected by fire
     !
     do fc = 1, num_soilc
        c = filter_soilc(fc)

        ! zero out the fire area

        farea_burned(c) = 0._r8
        baf_crop(c)     = 0._r8
        baf_peatf(c)    = 0._r8
        fbac(c)         = 0._r8
        fbac1(c)        = 0._r8
        cropf_col(c)    = 0._r8 
        lfc(c)          = 0._r8
        ! with NOFIRE, tree carbon is still removed in landuse change regions by the
        ! landuse code
     end do  ! end of column loop

   end associate

 end subroutine CNFireArea

end module CNFireNoFireMod
