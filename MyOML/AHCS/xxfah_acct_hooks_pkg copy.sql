flowchart TD
   A[Start preaccounting] -->B[Input: ControlId & TransactionID]
   B --> C[Initialize variables]
   C --> D[Query cur_events]
   D --> E{Process each record}
   
   E --> F{Check Layout Type}
   
   F -->|XXFAH_IFRS17_LAYOUT| G[Skip Processing]
   
   F -->|MIL Layout| H[Process Milly Layout]
   H --> H1{Check Business Unit}
   H1 -->|GS| H2[Map GS segments]
   H1 -->|EB| H3[Map EB segments]
   H1 -->|ILSA| H4[Map ILSA segments]
   H1 -->|ILNA| H5[Map ILNA segments]
   H1 -->|Others| H6[Map Milly Account]
   
   F -->|NMD Layout| I[Process NMD Layout]
   I --> I1[Map MD Account Value]
   
   F -->|O-11/ON-11/O-8| J[Process Oracle Layout]
   J --> J1{Check Key Type}
   J1 -->|RECOVERABLE VAT| J2[Map VAT segments]
   J1 -->|Others| J3[Map CCID segments]
   
   H2 & H3 & H4 & H5 & H6 --> K[Validate Account]
   I1 --> K
   J2 & J3 --> K
   
   K --> L[Update xxfah_passthrough_lines]
   
   L --> M{Error Handling}
   M -->|Success| N[Update Control Table - SUCCESS]
   M -->|Error| O[Log Error & Update Control Table - INVALID]
   
   N & O --> P[Return Status]
   P --> Q[End]
   
   subgraph "Error Handling"
   R[Log in xxfah_errors]
   S[Update transaction control status]
   T[Return ERROR status]
   end
   
   subgraph "Technical Details"
   U[Tables Used:
      - xxfah_passthrough_headers
      - xxfah_passthrough_lines
      - xxfah_transaction_cntrl
      - xxcus_interface_cntrl]
   V[Key Mappings:
      - Segments 1-7
      - Entity/Account/Centre
      - Fund/Product/Scheme]
   W[Status Updates:
      - SUCCESS/INVALID
      - LOAD/PREACCOUNTING stages]
   end
