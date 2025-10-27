# Live Analytics Dashboard

How to use mock DB:

```bash
pip install -r requirements.txt
```

```bash
python db/setupDB.py
```

```bash
uvicorn main:app --reload
```

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