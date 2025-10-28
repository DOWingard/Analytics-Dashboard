# Chebyshev Representation

We can represent any smooth-ish data curve on a chebyshev basis over [-1,1] that is analytic at the roots  
Cheby polynomial expansions can take be differentiated by recursion and easily root-solve

**Cheby Methods**

*   model('row1','row2')   ->   models row2 vs row1 then plots
*   modelderiv             ->   differentiates model and replots 
*   zero                   ->   RETURNS: roots of model