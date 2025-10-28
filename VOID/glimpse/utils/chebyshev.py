import numpy as np
from numpy.polynomial import Chebyshev

class Cheby:
    """
    Maps fxn to Chebyshev polynomial basis over [-1,1].
    """

    def __init__(self, degree: int):
        self.degree = degree
        self.poly = None  # Chebyshev object

    def express(self, func):
        """
        Express input function as a sum of Chebyshev polynomials.
        func: callable f(x)
        Returns: Chebyshev polynomial object
        """
        # Sample points (Chebyshev nodes)
        nodes = np.cos(np.pi * (np.arange(self.degree + 1) + 0.5) / (self.degree + 1))
        values = np.array([func(x) for x in nodes])
        coeffs = Chebyshev.fit(nodes, values, self.degree, domain=[-1,1]).coef
        self.poly = Chebyshev(coeffs, domain=[-1,1])
        return self.poly

    def deriv(self):
        """
        Recursively compute derivative of the Chebyshev polynomial.
        Returns: Chebyshev polynomial object representing the derivative
        """
        if self.poly is None:
            raise ValueError("Polynomial not yet expressed. Call express() first.")
        self.poly = self.poly.deriv()
        return self.poly

    def zero(self):
        """
        Find roots of the Chebyshev polynomial in [-1,1].
        Returns: array of roots
        """
        if self.poly is None:
            raise ValueError("Polynomial not yet expressed. Call express() first.")
        return self.poly.roots()
