# Live Analytics Dashboard

## Setup new DB

VSCode tasks to initalize container

tasks:   
    * [OPTIONAL] MAKECLEAN - only if stale db
    * Start VOID ABYSS

It is then ready to issue commands to and set up the PostgreSQL DB


**Install required packages**
```bash
pip install -r requirements.txt
```

**Database Setup**    

Check out the commands:  
```bash
./x.bat help
```

_Currently loads fake data_
```bash
./x.bat new
```

Check out the db:
```bash
./x.bat ping
```

## Access existing DB

VSCode tasks to safely bring up/down container

tasks:   
    * Bring ABYSS up
    * Bring ABYSS down
    
Check out the db:
```bash
./x.bat ping
```

## Open the UI interface  
Live plots from the db

```bash
uvicorn main:app --reload
```

## Accessing an existing container

VSCode tasks to bring up the container

tasks:   
    * [OPTIONAL] MAKECLEAN - only if stale db
    * Start PostgreSQL container

It is then ready to issue commnds to


# Contents

**[[CONTAINERS](.devcontainer/___CONTAINERS.md)]**

This analytics system exists on 2 containers:

    *   void-abyss  :: backend postgres server with public ssh server for remote access
    *   void-seeker :: [TODO] set up container to run the existing UI

**[[X.md](___X.md)]**   ::  _central command CLI_   

```./x.bat COMMAND```

    *   new       -> fresh new db  with info and 5 tables
    *   ping      -> ping full db info and 5 tables


**[[SCRIPTS.md](VOID/scripts/___SCRIPTS.md)]**

    *   pingDB    -> ping the db for current time
    *   dex       -> connect into to container terminal 
    *   updateEnv -> updates all the .env files based on ```scripts/.env```

**[[UTILS.md](VOID/utils/___UTILS.md)]**  ::  _composit scripts_   

    *   newDB     -> creates a fresh new db
    *   peek      -> fully peaks the db info



**[[DATABASE.md](VOID/db/___DATABASE.md)]**

    *   db   -> CLI to wrap python utils (--fill, --reset, --setup)
        -   fillYear  ->   fills sql db with 1 yr simulated data
        -   printDB   ->   print the db column titles
        -   resetDB   ->   resets db to uninitialized state
        -   setupDB   ->   set up db for the first time


**[[SENSE.md](VOID/glimpse/___SENSE.md)]**

*VOID SENSE - Class for real-time analysis*  

    *   void.help        ->   prints available commands
    *   void.printDB     ->   print all available columns from all DBs
    *   void.model       ->   plots the model row2 vs row1 
    *   void.modelDeriv  ->   derivative the model once and replots

**[[CHEBY.md](VOID/glimpse/utils/___CHEBY.md)]**

    *   cheby.model       ->  models row2 vs row1
    *   cheby.modelDeriv  ->  differentiates model once and replots
    *   cheby.zero        ->  RETURNS: roots of model


**[[SEEKR.md](VOID/seeker/___SEEKR.md)]**


Command the SEEKR using the HIVEMIND  
```bash
client/hivemind.bat --<FLAG>  
```
    --<FLAG> :
        * --ping     : ping db with VOID SEEKR 
        * --metrics  : return tables [OPTIONAL: *columns]
        * --runway   : return run way calculation from most recent entry



# Interactive terminal

Currently the live plot just pulls from all the stuff I have in the local db. 

## VOID MODELING

Uses a Chebyshev polynomial expansion over [-1,1] to represent the function
This allows us to recursively take any amount of derivatives to any function

***to see available datasets***
```bash
void.printDB()
```

To see all possible datasets you can compare, then use:
```bash
void.model('datasetx','datasety')
```
To take the derivative of the model:
```bash
void.modelDeriv()
```
This can me taken repeatedly.
