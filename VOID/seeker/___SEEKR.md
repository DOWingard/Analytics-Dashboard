# Use the HIVEMIND to make VOID SEEKR query VOID ABYSS

Querie the VOID ABYSS by sending VOID SEEKER using the HIVEMIND ツ 

## HIVEMIND CLI

Simple test ping:  
```bash
client/hivemind.bat --ping
```

Returns whole year data for all or optionally select columns, smart parses:

_default all_
```bash
client/hivemind.bat --metrics  
```
_specific columns_
```bash
client/hivemind.bat --metrics funds costs users #...
```

Compute runway from most recent table
```bash
client/hivemind.bat --runway
```