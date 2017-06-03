$output = 'C:\MOF'

Configuration PowerPlan_Sample
{
    Import-DscResource -ModuleName DSCR_PowerPlan
    Node localhost
    {
        cPowerPlan PowerPlan_Sample
        {
            Ensure = "Present"
            GUID = "381b4222-f694-41f0-9685-ff5bb260df2e"
            Name = "バランス"
            Active = $true
        }

        cPowerPlanSetting PowerPlanSetting_Sample
        {
            PlanGuid = 'ACTIVE'
            SettingGuid = 'PBUTTONACTION'
            Value = 2   #Hibernate
            AcDc = 'AC'
        }
    }
}

PowerPlan_Sample -OutputPath $output
Start-DscConfiguration -Path  $output -Verbose -wait

