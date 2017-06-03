$script:DataPath = Join-path $PSScriptRoot '\DATA'
$script:PlanListPath = Join-path $DataPath '\GUID_LIST_PLAN'
$script:PowerPlanAliases = Get-Content $PlanListPath -Raw | ConvertFrom-StringData

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [ValidateSet("Present","Absent")]
        [string]
        $Ensure = 'Present',

        [parameter(Mandatory = $true)]
        [string]
        $GUID,

        [parameter(Mandatory = $true)]
        [string]
        $Name,

        [bool]
        $Active = $false
    )
    $ErrorActionPreference = 'Stop'

    if($PowerPlanAliases.ContainsKey($GUID)){
        $GUID = $PowerPlanAliases.$GUID
    }

    $Plan = @(Get-PowerPlan -GUID $GUID)[0]
    if(-not $Plan){
        $Ensure = 'Absent'
        $Name = ''
        $Active = $false
    }
    else{
        $Ensure = 'Present'
        $Name = $Plan.ElementName
        $Active = $Plan.IsActive
    }

    $returnValue = @{
        Ensure = $Ensure
        GUID = $GUID
        Name = $Name
        Active = $Active
    }

    $returnValue
} # end of Get-TargetResource


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present","Absent")]
        [string]
        $Ensure = 'Present',

        [parameter(Mandatory = $true)]
        [string]
        $GUID,

        [parameter(Mandatory = $true)]
        [string]
        $Name,

        [bool]
        $Active = $false
    )
    $ErrorActionPreference = 'Stop'

    if($PowerPlanAliases.ContainsKey($GUID)){
        $GUID = $PowerPlanAliases.$GUID
    }

    try{
        # Ensure = "Absent"
        if($Ensure -eq 'Absent'){
            $Plan = (Get-PowerPlan $GUID)
            $PlanGUID = $Plan.InstanceId.Split('\')[1] -replace '[{}]'
            Write-Verbose ('Removing PowerPlan ({0})' -f $PlanGUID)
            if($Plan.IsActive){
                $NonActivePlan = Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | where {-not $_.IsActive} | select -First 1
                if(-not $NonActivePlan){
                    Write-Error "Couldn't deactivate the powerplan"
                }
                $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/SETACTIVE {0}' -f ($NonActivePlan.InstanceId.Split('\')[1] -replace '[{}]'))).ExitCode
                if($ExitCode -ne 0){
                    Write-Error "Couldn't deactivate the powerplan"
                }
            }
            $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/D {0}' -f $PlanGUID)).ExitCode
            if($ExitCode -ne 0){
                Write-Error 'Error occured'
            }
            else{
                Write-Verbose ('Success')
            }
        }
        else{
            # Ensure = "Present"
            if($Plan = Get-PowerPlan $GUID){
                $PlanGUID = $Plan.InstanceId.Split('\')[1] -replace '[{}]'
                if($Plan.ElementName -ne $Name){
                    $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/CHANGENAME {0} "{1}"' -f $PlanGUID, $Name)).ExitCode
                    if($ExitCode -ne 0){
                        Write-Error 'Error occured when changing the name of powerplan'
                    }
                }

                if($Active){
                    $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/SETACTIVE {0}' -f $PlanGUID)).ExitCode
                    if($ExitCode -ne 0){
                        Write-Error "Couldn't activate the powerplan"
                    }
                }
                elseif($Plan.IsActive){
                    $NonActivePlan = Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | where {-not $_.IsActive} | select -First 1
                    if(-not $NonActivePlan){
                        Write-Error "Couldn't deactivate the powerplan"
                    }
                    $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/SETACTIVE {0}' -f ($NonActivePlan.InstanceId.Split('\')[1] -replace '[{}]'))).ExitCode
                    if($ExitCode -ne 0){
                        Write-Error "Couldn't deactivate the powerplan"
                    }
                }
            }
            else{
                if($GUID -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){
                    Write-Error ('Invalid GUID format')
                }
                $BasePlan = Get-PowerPlan
                $BaseGuid = $BasePlan.InstanceId.Split('\')[1] -replace '[{}]'
                $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/DUPLICATESCHEME {0} {1}' -f $BaseGuid, $GUID)).ExitCode
                if($ExitCode -ne 0){
                    Write-Error "Couldn't create the powerplan"
                }
                $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/CHANGENAME {0} "{1}"' -f $GUID, $Name)).ExitCode
                if($ExitCode -ne 0){
                    Write-Error 'Error occured when changing the name of powerplan'
                }
                if($Active){
                    $ExitCode = (Start-Command -FilePath 'Powercfg.exe' -ArgumentList ('/SETACTIVE {0}' -f $GUID)).ExitCode
                    if($ExitCode -ne 0){
                        Write-Error "Couldn't activate the powerplan"
                    }
                }
            }
        }
    }
    catch{
        Write-Error $_.Exception.Message
    }

} # end of Set-TargetResource


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [ValidateSet("Present","Absent")]
        [string]
        $Ensure = 'Present',

        [parameter(Mandatory = $true)]
        [string]
        $GUID,

        [parameter(Mandatory = $true)]
        [string]
        $Name,

        [bool]
        $Active = $false
    )

    if($PowerPlanAliases.ContainsKey($GUID)){
        $GUID = $PowerPlanAliases.$GUID
    }

    try{
        $cState = (Get-TargetResource @PSBoundParameters)
        $ret =  $cState.Ensure -eq $Ensure
        if($Ensure -eq 'Absent'){
            return $ret
        }
        else{
            if($ret){
                return (($cState.Active -eq $Active) -and ($cState.Name -eq $Name))
            }
            else{
                return $false
            }
        }
    }
    catch{
        Write-Error $_.Exception.Message
    }
} # end of Test-TargetResource


function Get-PowerPlan {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0)]
        [AllowEmptyString()]
        [string]$GUID
    )

    if($PowerPlanAliases.ContainsKey($GUID)){
        $GUID = $PowerPlanAliases.$GUID
    }

    if($GUID){
        Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | where {$_.InstanceID -match $GUID}
    }
    else{
        Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan | where {$_.IsActive}
    }
}

function Start-Command {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string] $FilePath,
        [Parameter(Mandatory=$false, Position=1)]
        [string[]]$ArgumentList,
        [int]$Timeout = [int]::MaxValue
    )
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = $FilePath
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.Arguments = [string]$ArgumentList
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo
    $Process.Start() | Out-Null
    if(!$Process.WaitForExit($Timeout)){
        $Process.Kill()
        Write-Error ('Process timeout. Terminated. (Timeout:{0}s, Process:{1})' -f ($Timeout * 0.001), $FilePath)
    }
    $Process
}

Export-ModuleMember -Function *-TargetResource
