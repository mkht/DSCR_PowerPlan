$script:DataPath = Join-path $PSScriptRoot '\DATA'
$script:PlanListPath = Join-path $DataPath '\GUID_LIST_PLAN'
$script:SettingListPath = Join-path $DataPath '\GUID_LIST_SETTING'
$script:PowerPlanAliases = Get-Content $PlanListPath -Raw | ConvertFrom-StringData
$script:PowerPlanSettingAliases = Get-Content $SettingListPath -Raw | ConvertFrom-StringData

function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [string]
        $PlanGuid,

        [parameter(Mandatory = $true)]
        [string]
        $SettingGuid,

        [parameter(Mandatory = $true)]
        [int]
        $Value,

        [parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC", "Both")]
        [string]
        $AcDc = 'Both'
    )
    $ErrorActionPreference = 'Stop'

    Write-Verbose "Retrieving Power settings. { PlanGuid: $PlanGuid | SettingGuid: $SettingGuid }"
    $Setting = Get-PowerPlanSetting -PlanGuid $PlanGuid -SettingGuid $SettingGuid -Verbose:$false

    $returnValue = @{
        SettingGuid = $Setting.SettingGuid
        PlanGuid    = $Setting.PlanGuid
        Value       = $Value
        ACValue     = $Setting.ACValue
        DCValue     = $Setting.DCValue
    }
    Write-Verbose ("Current setting (AC: {0} | DC: {1})" -f $Setting.ACValue, $Setting.DCValue)

    $returnValue
} # end of Get-TargetResource

function Set-TargetResource {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]
        $PlanGuid,

        [parameter(Mandatory = $true)]
        [string]
        $SettingGuid,

        [parameter(Mandatory = $true)]
        [int]
        $Value,

        [parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC", "Both")]
        [string]
        $AcDc = 'Both'
    )
    $ErrorActionPreference = 'Stop'

    try {
        Set-PowerPlanSetting @PSBoundParameters
        Write-Verbose "Power setting has been changed successfully. { PlanGuid: $PlanGuid | SettingGuid: $SettingGuid | Value: $Value | AcDc: $AcDc }"
    }
    catch {
        Write-Error $_.Exception.Message
    }

} # end of Set-TargetResource

function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [string]
        $PlanGuid,

        [parameter(Mandatory = $true)]
        [string]
        $SettingGuid,

        [parameter(Mandatory = $true)]
        [int]
        $Value,

        [parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC", "Both")]
        [string]
        $AcDc = 'Both'
    )
    $ErrorActionPreference = 'Stop'
    $Result = $false
    $Current = $null

    Write-Verbose "Test started. { PlanGuid: $PlanGuid | SettingGuid: $SettingGuid | Value: $Value | AcDc: $AcDc }"
    try {
        $cState = (Get-TargetResource @PSBoundParameters)
        switch ($AcDc) {
            'AC' {
                $Result = ($cState.ACValue -eq $Value)
                $Current = $cState.ACValue
            }
            'DC' {
                $Result = ($cState.DCValue -eq $Value)
                $Current = $cState.DCValue
            }
            Default {
                if ($cState.ACValue -ne $Value) {
                    $Result = $false
                    $Current = $cState.ACValue
                }
                elseif ($cState.DCValue -ne $Value) {
                    $Result = $false
                    $Current = $cState.DCValue
                }
                else {
                    $Result = $true
                    $Current = $cState.ACValue
                }
            }
        }
    }
    catch {
        Write-Error $_.Exception.Message
    }

    if ($Result) {
        Write-Verbose ('[PASSED] Current: {0} / Desired : {1}' -f $Current, $Value)
    }
    else {
        Write-Verbose ('[FAILED] Current: {0} / Desired : {1}' -f $Current, $Value)
    }

    $Result
} # end of Test-TargetResource

function Get-PowerPlan {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$GUID
    )

    if ($PowerPlanAliases.ContainsKey($GUID)) {
        $GUID = $PowerPlanAliases.$GUID
    }

    if ($GUID -eq 'ALL') {
        Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan
    }
    elseif ($GUID) {
        Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | Where-Object {$_.InstanceID -match $GUID}
    }
    else {
        Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | Where-Object {$_.IsActive}
    }
}

function Get-PowerPlanSetting {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $false, ValueFromPipeline)]
        [string[]]
        $PlanGuid,

        [parameter(Mandatory = $true)]
        [string]
        $SettingGuid
    )

    Begin {
        # 電源プラン系のグループポリシーが設定されていると電源設定の取得ができないので一時的に無効化する
        $GPReg = Backup-GroupPolicyPowerPlanSetting
        if ($GPReg) {
            Disable-GroupPolicyPowerPlanSetting
        }
    }

    Process {
        foreach ($planid in $PlanGuid) {
            if ($PowerPlanAliases -and $PowerPlanAliases.ContainsKey($planid)) {
                $planid = $PowerPlanAliases.$planid
            }
            if ($PowerPlanSettingAliases -and $PowerPlanSettingAliases.ContainsKey($SettingGuid)) {
                $SettingGuid = $PowerPlanSettingAliases.$SettingGuid
            }
            $planid -replace '[{}]'
            $SettingGuid = $SettingGuid -replace '[{}]'

            $Plan = @(Get-PowerPlan $planid)[0]
            if (-not $Plan) {
                Write-Error "Couldn't get PowerPlan"
            }

            $planid = $Plan.InstanceId.Split('\')[1] -replace '[{}]'

            $ReturnValue = @{
                PlanGuid    = $planid
                SettingGuid = $SettingGuid
                ACValue     = ''
                DCValue     = ''
            }

            foreach ($Power in ('AC', 'DC')) {
                $Key = ('{0}Value' -f $Power)
                $InstanceId = ('Microsoft:PowerSettingDataIndex\{{{0}}}\{1}\{{{2}}}' -f $planid, $Power, $SettingGuid)
                $Instance = (Get-CimInstance -Name root\cimv2\power -Class Win32_PowerSettingDataIndex | Where-Object {$_.InstanceID -eq $InstanceId})
                if (-not $Instance) { Write-Error "Couldn't get power settings"; return }
                $ReturnValue.$Key = [int]$Instance.SettingIndexValue
            }

            $ReturnValue
        }
    }

    End {
        if ($GPReg) {
            # 無効化した電源プラン系のグループポリシーを再設定する
            Restore-GroupPolicyPowerPlanSetting -GPRegArray $GPReg
        }
    }
}

function Set-PowerPlanSetting {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $false, ValueFromPipeline)]
        [string[]]
        $PlanGuid,

        [parameter(Mandatory = $true)]
        [string]
        $SettingGuid,

        [parameter(Mandatory = $true)]
        [int]
        $Value,

        [ValidateSet("AC", "DC", "Both")]
        [string]
        $AcDc = 'Both',

        [switch]$PassThru
    )
    Begin {
        $local:VerbosePreference = "SilentlyContinue"
        # 電源プラン系のグループポリシーが設定されていると電源設定の取得ができないので一時的に無効化する
        $GPReg = Backup-GroupPolicyPowerPlanSetting
        if ($GPReg) {
            Disable-GroupPolicyPowerPlanSetting
        }
    }
    Process {
        foreach ($planid in $PlanGuid) {
            if ($PowerPlanAliases -and $PowerPlanAliases.ContainsKey($planid)) {
                $planid = $PowerPlanAliases.$planid
            }
            if ($PowerPlanSettingAliases -and $PowerPlanSettingAliases.ContainsKey($SettingGuid)) {
                $SettingGuid = $PowerPlanSettingAliases.$SettingGuid
            }
            $planid = $planid -replace '[{}]'
            $SettingGuid = $SettingGuid -replace '[{}]'

            if ($AcDc -eq 'Both') {
                [string[]]$Target = ('AC', 'DC')
            }
            else {
                [string[]]$Target = $AcDc
            }

            $Plan = @(Get-PowerPlan $planid)[0]
            if (-not $Plan) {
                Write-Error "Couldn't get PowerPlan"
            }

            $planid = $Plan.InstanceId.Split('\')[1] -replace '[{}]'

            foreach ($Power in $Target) {
                $InstanceId = ('Microsoft:PowerSettingDataIndex\{{{0}}}\{1}\{{{2}}}' -f $planid, $Power, $SettingGuid)
                $Instance = Get-CimInstance -Name root\cimv2\power -Class Win32_PowerSettingDataIndex | Where-Object {$_.InstanceID -eq $InstanceId}
                if (-not $Instance) { Write-Error "Couldn't get power settings"; return }
                $Instance | ForEach-Object {$_.SettingIndexValue = $Value}
                Set-CimInstance -CimInstance $Instance
            }

            if ($PassThru) {
                Get-PowerPlanSetting -PlanGuid $planid -SettingGuid $SettingGuid
            }
        }
    }
    End {
        if ($GPReg) {
            # 無効化した電源プラン系のグループポリシーを再設定する
            Restore-GroupPolicyPowerPlanSetting -GPRegArray $GPReg
        }
    }
}

function Backup-GroupPolicyPowerPlanSetting {
    $RegKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
    if (Test-Path $RegKey) {
        $Array = @()
        Get-ChildItem $RegKey | ForEach-Object {
            $Path = $_.PSPath
            foreach ($Prop in $_.Property) {
                $Array += @{
                    Path  = $Path
                    Name  = $Prop
                    Value = Get-ItemPropertyValue -Path $Path -Name $Prop
                }
            }
        }
        $Array
    }
}

function Restore-GroupPolicyPowerPlanSetting {
    Param(
        [HashTable[]]$GPRegArray
    )

    foreach ($Item in $GPRegArray) {
        if (-not (Test-Path $Item.Path)) {
            New-Item -Path $Item.Path -ItemType Directory -Force | Out-Null
        }
        New-ItemProperty @Item -Force | Out-Null
    }
}

function Disable-GroupPolicyPowerPlanSetting {
    $RegKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
    Remove-item $RegKey -Recurse -Force | Out-Null
}

Export-ModuleMember -Function *-TargetResource
