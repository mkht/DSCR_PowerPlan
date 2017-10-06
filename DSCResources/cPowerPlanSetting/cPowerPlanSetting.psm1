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

    # PlanGuid = 'SCHEME_ALL'の場合、$Settingが複数Objectの配列になる場合がある
    # そのままではGet-TargetResourceで返せないので、あまり良い方法ではないが、最初の1つに絞って返す
    $returnValue = @{
        SettingGuid = @($Setting)[0].SettingGuid
        PlanGuid    = @($Setting)[0].PlanGuid
        Value       = $Value
        ACValue     = @($Setting)[0].ACValue
        DCValue     = @($Setting)[0].DCValue
    }
    foreach ($set in $Setting) {
        Write-Verbose ("Current setting (PlanGuid:{0} | AC: {1} | DC: {2})" -f $set.PlanGuid, $set.ACValue, $set.DCValue)
    }

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
    $Result = $true

    Write-Verbose "Test started. { PlanGuid: $PlanGuid | SettingGuid: $SettingGuid | Value: $Value | AcDc: $AcDc }"
    if ($AcDc -eq 'Both') { $Mode = 'ACDC'}
    else { $Mode = $AcDc }

    try {
        $Settings = Get-PowerPlanSetting -PlanGuid $PlanGuid -SettingGuid $SettingGuid -Verbose:$false
        #SCHEME_ALLの場合全てのPowerPlanの設定値をチェックする必要がある
        foreach ($cState in $Settings) {
            switch -RegEx ($Mode) {
                'AC' {
                    if ($cState.ACValue -ne $Value) {
                        $Result = $false
                        Write-Verbose ('[FAILED] Plan: {0} / Type: {1} / CurrentValue: {2} / DesiredValue : {3}' -f $cState.PlanGuid, 'AC', $cState.ACValue, $Value)
                    }
                    else {
                        Write-Verbose ('[PASSED] Plan: {0} / Type: {1} / CurrentValue: {2} / DesiredValue : {3}' -f $cState.PlanGuid, 'AC', $cState.ACValue, $Value)
                    }
                }
                'DC' {
                    if ($cState.DCValue -ne $Value) {
                        $Result = $false
                        Write-Verbose ('[FAILED] Plan: {0} / Type: {1} / CurrentValue: {2} / DesiredValue : {3}' -f $cState.PlanGuid, 'DC', $cState.DCValue, $Value)
                    }
                    else {
                        Write-Verbose ('[PASSED] Plan: {0} / Type: {1} / CurrentValue: {2} / DesiredValue : {3}' -f $cState.PlanGuid, 'DC', $cState.DCValue, $Value)
                    }
                }
            }
        }
    }
    catch {
        Write-Error $_.Exception.Message
        $Result = $false
    }

    if ($Result) {
        Write-Verbose ('ALL TEST PASSED')
    }
    else {
        Write-Verbose ('SOME TEST FAILED')
    }

    $Result
} # end of Test-TargetResource

function Get-PowerPlan {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [Alias('PlanGuid')]
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
            $planid = $planid -replace '[{}]'
            $SettingGuid = $SettingGuid -replace '[{}]'

            $Plans = @(Get-PowerPlan $planid)   #PowerPlanは複数取得される場合あり
            if (-not $Plans) {
                Write-Error "Couldn't get PowerPlan"
            }

            foreach ($Plan in $Plans) {
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

            $Plans = @(Get-PowerPlan $planid)   #PowerPlanは複数取得される場合あり
            if (-not $Plans) {
                Write-Error "Couldn't get PowerPlan"
            }
            foreach ($Plan in $Plans) {
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

Export-ModuleMember -Function ('Get-TargetResource', 'Test-TargetResource', 'Set-TargetResource', 'Get-PowerPlan', 'Get-PowerPlanSetting', 'Set-PowerPlanSetting')
