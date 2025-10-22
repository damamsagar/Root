graph TD
  A[XXFAH_GET_MAPPING_OUTPUT_PKG] --> B[GetSegmentValues]
  A --> C[Account Related Functions]
  A --> D[Product Related Functions] 
  A --> E[Tax Fund Related Functions]
  A --> F[Cost Center Related Functions]
  A --> G[Oracle Layout Functions]

  B --> B1[Validates segment values against XXAGIS_VALUE_SET_VALUES]

  C --> C1[GsMillyAccountValue]
  C --> C2[EbMillyAccountValue]
  C --> C3[IlnaMillyAccountValue]
  C --> C4[IlnaAccountValue]
  C --> C5[ValidateAccount]

  D --> D1[GsMillyProductValue]
  D --> D2[EbProductValue]
  D --> D3[IlnaProductValue]
  D --> D4[IlsamillyProductValue]

  E --> E1[GsMillyTaxFundValue]
  E --> E2[EbTaxFundValue]
  E --> E3[IlsaTaxFundValue]

  F --> F1[GsMillyBudgetCentreValue]
  F --> F2[IlsaMillyCostCentreValue]
  F --> F3[IlnaCostCentreValue]

  G --> G1[CcidToBalEntity]
  G --> G2[CcidToBudCtr]
  G --> G3[CcidToAcct]
  G --> G4[CcidToProduct]
