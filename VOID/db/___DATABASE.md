# PostgreSQL database
# Mini API ```db.bat --<method>```

All of the util functions are wrapped in this method
```bash
db/db.bat --<method>
```

* --print : printColumns.py  ->  prints db structure
* --peak  : peek.py          ->  peeks first 5 tables in db
* --fill  : fillYear.py      ->  fills 1 year of simulated data into db
* --reset : resetDB.py       ->  resets db to empty
* --setup : setubDB.py       ->  stores db into PostgreSQL container

