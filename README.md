DSCR_PowerPlan
====

PowerShell DSC Resource & Functions for Power Plan configuration

## Install
You can install Resource through [PowerShell Gallery](https://www.powershellgallery.com/packages/DSCR_PowerPlan/).
```Powershell
Install-Module -Name DSCR_PowerPlan
```

## DSC Resources
* **cPowerPlan**
PowerShell DSC Resource for create / change / remove Power Plan.

* **cPowerPlanSettings**
PowerShell DSC Resource for modify Power settings & options.

## Properties

### cPowerPlan
+ [String] **Ensure** (Write):
    + Specifies existence state of Power Plan.
    + The default value is `Present`. { `Present` | `Absent` }

+ [String] **Name** (Required):
    + The Name of Power Plan.

+ [String] **Description** (Write):
    + The Description of Power Plan.

+ [String] **GUID** (Key):
    + The GUID of Power Plan.
    + If you want to create Original Plan, should specify unique GUID.
    + If you want to set system default Plans, you can use aliases. {`SCHEME_MAX` | `SCHEME_MIN` | `SCHEME_BALANCED`}

+ [Boolean] **Active** (Write):
    + Specifies set or unset Power Plan as Active.
    + The default value is `$false`

### cPowerPlanSettings
+ [String] **SettingGuid** (Key):
    + The GUID of Power Setting.
    + You can obtain GUIDs by executing `powercfg.exe /Q` command
    + You can also use some aliases. The list of aliases is [here](https://github.com/mkht/DSCR_PowerPlan/blob/master/DSCResources/cPowerPlanSetting/DATA/GUID_LIST_SETTING).

+ [String] **PlanGuid** (Key):
    + The GUID of target Power Plan.
    + You can also use aliases. {`ACTIVE` | `ALL` | `SCHEME_MAX` | `SCHEME_MIN` | `SCHEME_BALANCED`}
    + If you specify the aliase `ALL`, All Power Plans on the current system to be targeted.

+ [String] **AcDc** (Key):
    + You can choose {`AC` | `DC` | `Both`}
    + The default value is `Both`

+ [UInt32] **Value** (Required):
    + Specifies Power Setting value.


## Examples
### cPowerPlan
+ **Example 1**: Set "Balanced" Power Plan to Active
```Powershell
Configuration Example1
{
    Import-DscResource -ModuleName DSCR_PowerPlan
    cPowerPlan Balanced_Active
    {
        Ensure = "Present"
        GUID   = "SCHEME_BALANCED"   # You can use alias
        Name   = "Balanced"
        Active  = $true
    }
}
```

+ **Example 2**: Create original Power Plan "PlanA"
```Powershell
Configuration Example2
{
    Import-DscResource -ModuleName DSCR_PowerPlan
    cPowerPlan PlanA
    {
        Ensure = "Present"
        GUID   = "ad98b5c7-06a1-493f-b611-da04c574e8b5"   # Unique GUID
        Name   = "PlanA"
        Description = "This is original Power Plan"
    }
}
```

### cPowerPlanSettings
+ **Example 1**: Set the duration of entering sleep to 5 minutes.
```Powershell
Configuration Example1
{
    Import-DscResource -ModuleName DSCR_PowerPlan
    cPowerPlanSetting Sleep_5Min
    {
        PlanGuid    = 'ACTIVE'
        SettingGuid = 'STANDBYIDLE'
        Value       = 300   #sec
        AcDc        = 'Both'
    }
}
```
----
## Functions
You can use some functions to set Power Plan
### Get-PowerPlan
Get Power Plans on the current system.
```PowerShell
PS C:\> Get-PowerPlan -GUID 'ACTIVE'
Caption        :
Description    : Automatically balances performance with...
ElementName    : Balanced
InstanceID     : Microsoft:PowerPlan\{381b4222-f694-41f0-9685-ff5bb260df2e}
IsActive       : True
PSComputerName :
```
### Get-PowerPlanSetting
Get specified settings of Power Plan.
```PowerShell
PS C:\> Get-PowerPlanSetting -PlanGuid 'ACTIVE' -SettingGuid 'PBUTTONACTION'
Name                           Value
----                           -----
SettingGuid                    7648efa3-dd9c-4e3e-b566-50f929386280
DCValue                        3
ACValue                        3
PlanGuid                       381b4222-f694-41f0-9685-ff5bb260df2e
```

### Set-PowerPlanSetting
Set specified settings of Power Plan.
```PowerShell
PS C:\> Set-PowerPlanSetting -PlanGuid 'ACTIVE' -SettingGuid 'LIDACTION' -Value 1 -AcDc 'Both'
```
----
## ChangeLog
### 1.2.0
+ Support new aliases in Windows 10 version 1803

### 1.1.1
+ bug fix [#6](https://github.com/mkht/DSCR_PowerPlan/issues/6)

### 1.1.0
+ Support to set all power plans at once in `cPowerPlanSetting` (see [example](Example/))
+ Support hidden aliases in `cPowerPlanSetting`
+ Support new aliases in Windows 10 Fall Creators Update
+ Several useful functions are now available (`Get-PowerPlan`, `Get-PowerPlanSetting`, `Set-PowerPlanSetting`)

### 1.0.0
+ Add "Description" property for cPowerPLan
+ bug fix
