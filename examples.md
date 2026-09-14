# Examples

Same tool. Different nomenclature. Ask an agent to reshape the *installed* script toward one of these (or your own). Delete code for rules you drop; it is not precious.

## 1. Default (this repo)

Kebab terms. Optional leading date (`YY` / `YYMM` / `YYMMDD`). Optional trailing version (`v01`, `v0.1.2`) or batch (`001`). Extension casing kept.

```
260812-taxes-2025-receipts-v01.pdf
260812-holidays-europe-roadtrip-001.jpg
2608-3d-drone-frame-v02.step
26-ref-linux-kernel-guide.pdf
my-tax-receipt.PDF
```

Messy inputs become:

```
My Tax Receipt 2025.PDF          →  my-tax-receipt-2025.PDF
Holiday Europe Roadtrip 01.jpg   →  holiday-europe-roadtrip-001.jpg
Contract_Signed_V01.docx         →  contract-signed-v01.docx
3D_Drone_Frame_v02.STEP          →  3d-drone-frame-v02.STEP
```

## 2. PascalCase + underscore batch

Words TitleCased and concatenated. Underscore only before a batch or version suffix. No hyphens. No leading compact date token.

Edit toward: build a Pascal stem from term words; join suffix with `_`; drop kebab separators and `YYMMDD` date peel (or keep dates as their own Pascal segment if you want them).

```
ThisIsADifferentCaseSystem_0012.jpg
HolidayEuropeRoadtrip_0001.jpg
TaxReceipt2025_v01.pdf
DroneFrame_v02.step
LinuxKernelGuide.pdf
```

Messy inputs become:

```
My Tax Receipt 2025.PDF          →  MyTaxReceipt2025.PDF
Holiday Europe Roadtrip 01.jpg   →  HolidayEuropeRoadtrip_001.jpg
Contract_Signed_V01.docx         →  ContractSigned_v01.docx
3D_Drone_Frame_v02.STEP          →  3DDroneFrame_v02.STEP
```

## 3. ISO date + snake_case

`YYYY-MM-DD` or `YYYY-MM` when a date is present; otherwise lowercase terms with underscores. Version or batch still at the end, also underscore-separated.

Edit toward: emit ISO dates instead of `YYMMDD`; join with `_`; lowercase everything in the stem; keep extension policy as you like.

```
2026-09-14_holiday_europe_roadtrip_001.jpg
2026-08_tax_receipts_v01.pdf
2026-08-12_3d_drone_frame_v02.step
ref_linux_kernel_guide.pdf
```

Messy inputs become:

```
My Tax Receipt 2025.PDF          →  tax_receipt_2025.PDF
Holiday Europe Roadtrip 01.jpg   →  holiday_europe_roadtrip_001.jpg
Contract_Signed_V01.docx         →  contract_signed_v01.docx
260812-taxes-receipts.pdf        →  2026-08-12_taxes_receipts.pdf
```
