# WE Energies Home Energy Cost Modeling Script

This PowerShell script estimates and compares home energy costs under different WE Energies rate plans using 15-minute interval data from an Enphase solar system. It supports standard net metering and time-of-use (TOU) billing, while accounting for EV credits, meter fees, and holiday off-peak adjustments.

## 🔧 Features

- Models **standard net metering** and **time-of-use (TOU)** billing plans
- Handles **EV charging credits** with configurable limits
- Incorporates **fixed daily meter costs** and monthly fees
- Applies **different buyback rates for summer vs. non-summer**
- Recognizes **WE Energies off-peak holidays** (e.g., Memorial Day, Thanksgiving)
- Outputs **monthly summaries** and **exportable CSV** reports
- Rounds all monetary values to **two decimal places**

---

## 📁 Input Format

Input must be a CSV file (e.g., `enphase-data.csv`) with the following columns:

```
Date/Time,Energy Produced (Wh),Energy Consumed (Wh)
2024-01-01 00:00,150,350
2024-01-01 00:15,200,400
...
```

- Energy values must be in **watt-hours**.
- The script converts them to **kilowatt-hours (kWh)**.

---

## ⚙️ Configuration

Edit these parameters near the top of the script:

```powershell
$inputFile = "enphase-data.csv"
$peakHourstart = 8          # Can be 7, 8, or 9 for TOU simulation
$evCreditLimit = 400        # Monthly EV credit cap in kWh
```

All other tariff-related variables (rates, fees, holidays) are defined in the same section and commented.

---

## 📤 Output

The script generates an output file `output.csv` that includes monthly summaries for:

- Standard billing (with and without solar)
- TOU billing (with and without solar)
- EV credit impact
- Fixed service costs and buyback adjustments

Each row represents a month.

---

## ✅ Usage

1. Place `enphase-data.csv` in the same directory as the script.
2. Open PowerShell and run:

```powershell
.\energy-cost-model.ps1
```

3. Review the `output.csv` file for your month-by-month cost analysis.

---

## 🚧 Roadmap

Planned features for future versions:

- 🔋 Battery storage simulation for TOU arbitrage
- 📊 Annual rollup summaries and visualizations
- 🧪 Batch scenario testing (e.g., different peak start times)

---

## 🧠 Author

**Scott Bowe**  
Greendale, WI
