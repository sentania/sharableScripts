#function definition
function Is-WEnergiesHoliday {
    param(
        [datetime]$date
    )

    $year = $date.Year
    $holidays = @()

    # Fixed-date holidays
    $holidays += [datetime]::new($year, 1, 1)     # New Year's Day
    $holidays += [datetime]::new($year, 7, 4)     # Independence Day
    $holidays += [datetime]::new($year, 12, 25)   # Christmas Day

    # Memorial Day = last Monday in May
    $holidays += (31..25 | ForEach-Object {
        $d = [datetime]::new($year, 5, $_)
        if ($d.DayOfWeek -eq 'Monday') { return $d }
    })[0]

    # Labor Day = first Monday in September
    $holidays += (1..7 | ForEach-Object {
        $d = [datetime]::new($year, 9, $_)
        if ($d.DayOfWeek -eq 'Monday') { return $d }
    })[0]

    # Thanksgiving = fourth Thursday in November
    $holidays += (1..30 | ForEach-Object {
        $d = [datetime]::new($year, 11, $_)
        if ($d.DayOfWeek -eq 'Thursday') { return $d }
    })[3]  # 4th Thursday

    return $holidays | Where-Object { $_.Date -eq $date.Date } | Measure-Object | Select-Object -ExpandProperty Count | ForEach-Object { $_ -gt 0 }
}

# Define Input and Output File Path
$inputFile = "enphase-data.csv"

# ToU Peak Hour Start
$primePeakHourstart = 7                        # Edit to simulate different ToU peak windows, 7, 8 and 9 are current options for WE Energies
$loadShift = 400                              # Kwh to load shift from off-peak to peak, to reduce peak sell back.

# Adjust the following if you don't have an EV
$evCreditLimit = 400                        # kwH limit of EV Credit, set to 0 if this does not apply

# Fixed Rates
$firstMeterDailyCost = 0.49315              # Daily cost of first meter
$secondMeterDailyCost = 0.5951              # Daily cost of second meter
$environmentControlCharge = 0.00056         # Surchage per KW hour Net Consumed
$lowEnergyAssistanceFee = 3.15              #Fixed Monthly Rate

# Energy cost rates
$energyCostPerKwh = 0.18325                 # Cost per kWh
$buybackRatePerKwh = 0.03177                # Buyback rate for excess energy
$onPeakKwh = 0.27006
$offPeakKwh = 0.10387
$summerOnPeakBuyBackKwh = 0.04064
$summerOffPeakBuyBackKwh = 0.02852
$nonSummerOnPeakBuyBackKwh = 0.03411
$nonSummerOffPeakBuyBackKwh = 0.02931
$stdEVCredit = .04                             # Discount per KW Midnight to 8 am
$touEVCredit = 0.01000
#tuneables unlikely to need editing
$peakHoursEnd = $primePeakHourstart + 12         #calculate the end of peak period based on the peak starting time
$buyBackSummerMonths = 6,7,8,9              # WE energies allows a different buy back for summer vs non-summer so we need to identify them
$offPeakDaysofWeek = 0,6                    # saturday's and sunday's are always off peak


#process our input data and convert inputs from Wh to Kwh
$powerInputData = import-csv -path $inputFile
$powerdata = @()
foreach ($record in $powerInputData)
{
    $temp = "" | select datetime, production, consumption
    $temp.datetime = get-date ($record."Date/Time")
    $temp.production = $record."Energy Produced (Wh)" / 1000
    $temp.consumption = $record."Energy Consumed (Wh)" / 1000
    $powerdata += $temp
}


$monthlyData = $powerdata | Group-Object { $_.DateTime.Year},  {$_.DateTime.Month } # Group our input data into an array grouped by year, month

$i = 0
while ($i -lt 3 )
{
    $summaryData = @()
    $peakHourstart = $primePeakHourstart + $i
    Write-host "Calculating with Peak start of " $peakHourStart
    foreach ($month in $monthlyData)
    {

        $monthEVConsumption = 0
        $temp = "" | select month, grossConsumption, peakConsumption, offPeakConsumption, `
                            grossProduction, peakProduction, offPeakProduction, stdNoSolarEnergyCost ,touNoSolarCost, `
                            stdSolarElectricCost, touSolarElectricCost, touSolarLoadShiftElectricCost, staticServiceCost, stdEVSavings, touEVSavings, stdNoSolarTotal, `
                            touNoSolarTotal, stdSolarTotal, touSolarTotal, touSolarLoadShiftTotal
        $temp.month = $month.name
        $temp.staticServiceCost = $lowEnergyAssistanceFee
        $currentYear = $month.Name.split(',')[0]
        $currentMonth = $month.Name.split(',')[1]
        $daysInMonth = [datetime]::DaysInMonth($currentYear,$currentMonth)
        
        # THis is some of the tricky processing, process all data inputs for the month and bucket them into gross, peak, offpeak buckets
        foreach ($datapoint in $month.group)
        {
            #Does this datapoint fall on a WE energies holiday?
            $isHoliday = Is-WEnergiesHoliday -date $datapoint.datetime

            $temp.grossConsumption += $datapoint.consumption
            $temp.grossProduction += $datapoint.production
            if ($datapoint.datetime.hour -lt 8)
            {
                $monthEVConsumption += $datapoint.consumption
            }
            if (
                ($datapoint.datetime.hour -ge $peakHourstart -and $datapoint.datetime.hour -lt $peakHoursEnd) -and
                ($offPeakDaysofWeek -notcontains [int] $datapoint.datetime.DayOfWeek) -and !$isHoliday )
            {
                $temp.peakConsumption += $datapoint.consumption
                $temp.peakProduction += $datapoint.production
            }
            else
            {
                $temp.offPeakConsumption += $datapoint.consumption
                $temp.offPeakProduction += $datapoint.production
            }

        }    
        #Determine standard net metering cost of electrical consumption
        $netConsumption = $temp.grossConsumption - $temp.grossProduction
        if ($netConsumption -gt 0)
        {
            $temp.stdSolarElectricCost = $netConsumption * ($energyCostPerKwh + $environmentControlCharge)
        }
        else
        {
            $temp.stdSolarElectricCost = $netConsumption * $buybackRatePerKwh
        }
        
    #Determine TOU net metering cost of electrical consumption
        $touPeakNetConsumption = $temp.peakConsumption - $temp.peakProduction
        $touOffPeakNetConsumption = $temp.offPeakConsumption - $temp.offPeakProduction

        #do we use the summer or non-summer peak buyback
        if ($buyBackSummerMonths -contains $currentMonth)
        {
            $peakBuyBack = $summerOnPeakBuyBackKwh
            $offPeakBuyBack = $summerOffPeakBuyBackKwh
        }

        else
        {
            $peakBuyBack = $nonSummerOnPeakBuyBackKwh
            $offPeakBuyBack = $nonSummerOffPeakBuyBackKwh       
        }

        if ($touPeakNetConsumption -gt 0)
        {
            $touPeakCost = $touPeakNetConsumption * ($onPeakKwh + $environmentControlCharge)
        }
        else
        {
            $touPeakCost = $touPeakNetConsumption * $peakBuyBack
        }

        if ($touOffPeakNetConsumption -gt 0)
        {
            $touOffPeakCost = $touOffPeakNetConsumption * ($offPeakKwh + $environmentControlCharge)
        }
        else
        {
            $touOffPeakCost = $touOffPeakNetConsumption * $offPeakBuyBack
        }
        $temp.touSolarElectricCost = [math]::Round(($touOffPeakCost + $touPeakCost),2)
        $temp.touNoSolarCost = [math]::Round((($temp.peakConsumption * $onPeakKwh) + ($temp.offPeakConsumption * $offPeakKwh)),2)

        #Determine TOU net metering cost of electrical consumption with load shift
        $touLoadShiftPeakNetConsumption = ($temp.peakConsumption + $loadShift) - $temp.peakProduction
        $touLoadShiftOffPeakNetConsumption = ($temp.offPeakConsumption - $loadShift)- $temp.offPeakProduction
        

        if ($touLoadShiftPeakNetConsumption -gt 0)
        {
            $touLoadShiftPeakCost = $touLoadShiftPeakNetConsumption * ($onPeakKwh + $environmentControlCharge)
        }
        else
        {
            $touLoadShiftPeakCost = $touLoadShiftPeakNetConsumption * $peakBuyBack
        }

        if ($touLoadShiftOffPeakNetConsumption -gt 0)
        {
            $touLoadShiftOffPeakCost = $touLoadShiftOffPeakNetConsumption * ($offPeakKwh + $environmentControlCharge)
        }
        else
        {
            $touLoadShiftOffPeakCost = $touLoadShiftOffPeakNetConsumption * $offPeakBuyBack
        }

        $temp.touSolarLoadShiftElectricCost = [math]::Round(($touLoadShiftOffPeakCost + $touLoadShiftPeakCost),2)

        #Apply EV Credit 
        if ($monthEVConsumption -gt $evCreditLimit)
        {
            $monthEVConsumption = $evCreditLimit
        }

        #make sure our summaries are populated/calculated
        $temp.stdEVSavings = [math]::Round(($monthEVConsumption * $stdEVCredit),2)
        $temp.touEVSavings = [math]::Round(($monthEVConsumption * $touEVCredit),2)
        $temp.staticServiceCost += [math]::Round((($secondMeterDailyCost + $firstMeterDailyCost) * $daysInMonth),2)
        $temp.stdNoSolarEnergyCost  = [math]::Round(($temp.grossConsumption * $energyCostPerKwh),2)
        $temp.stdNoSolarTotal = [math]::Round(($temp.staticServiceCost + $temp.stdNoSolarEnergyCost  - $temp.stdEVSavings),2)
        $temp.touNoSolarTotal = [math]::Round(($temp.staticServiceCost + $temp.touNoSolarCost - $temp.touEVSavings),2)
        $temp.stdSolarTotal = [math]::Round(($temp.staticServiceCost + $temp.stdSolarElectricCost - $temp.stdEVSavings),2)
        $temp.touSolarTotal = [math]::Round(($temp.staticServiceCost + $temp.touSolarElectricCost - $temp.touEVSavings),2)
        $temp.touSolarLoadShiftTotal = [math]::Round(($temp.staticServiceCost + $temp.touSolarLoadShiftElectricCost - $temp.touEVSavings),2)
        $summaryData += $temp
    }

    #output to a CSV for further analysis
    $filename = "output-" + $peakHourstart +".csv"
    $summaryData | Export-Csv -Path $filename -NoTypeInformation
    $i++
}