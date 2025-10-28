# General QOL scripts



## ```dex.bat``` : Connect into container bash via docker exec with```--<user>```.

_The script takes a ```--<user>``` flag that is currently just set to the main superuser ```--null``` or the api bot ```--seek```:_
```bash
scripts/dex.bat --<user>
```

## ```pingDB.bat``` : Ping the database for current time forn given ```--<user>```.

_The script takes a ```--<user>``` flag that is currently just set to the main superuser ```--null``` or the api bot ```--seek```:_
```bash
scripts/pingDB.bat --<user>
```

## ```updateEnv.bat```: Update all .env files.

Make changes to ```.env``` in root,
then call 
```bash
scripts/updateEnv.bat
```
to update all the .env files.