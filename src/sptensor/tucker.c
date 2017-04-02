/*
    This file is part of ParTI!.

    ParTI! is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    ParTI! is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with ParTI!.
    If not, see <http://www.gnu.org/licenses/>.
*/

#include <ParTI.h>
#include "sptensor.h"
#include <stdlib.h>

#if 0

/*
  (sb) TODO:
  - Get to know types of each variable
  - Norm & Eigen calculation from cuSOLVER
  - Implement one-copy version of sspTTM
*/

int sptTuckerDecomposition(
    sptSparseTensor     *X,
    const size_t        R[],
    double              tol /* = 1.0e-4 */,
    unsigned            maxiters /* = 50 */,
    const size_t        dimorder[]
) {
    size_t nmodes = X->nmodes;
    sptSemiSparseTensor *U = malloc(nmodes * sizeof *U);
    sptSemiSparseTensor core;
    unsigned iter;
    double fit = 0;
    for(iter = 0; iter < maxiters; ++iter) {
        double fitold = fit;
        size_t ni;
        for(ni = 0; ni < nmodes; ++ni) {
            size_t n = dimorder[ni];
            size_t m;
            // Utilde = ttm(X, U, -n, 't');
            for(m = 0; m < nmodes; ++m) {
                if(m != n) {
                    sptSemiSparseTensorMulMatrix(Utilde, X, U[m], m);
                }
            }
            // U[n] = nvecs(Utilde, n, R[n]);
        }

        // core = ttm(Utilde, U, n, 't');
        sptSemiSparseTensorMulMatrix(core, Utilde, U[0], nmodes-1);

        // normresidual = hypot(normX, norm(core));
        // fit = 1 - normresidual / normX;
        // fitchange = abs(fitold - fit);

        // if(iter != 0 && fitchange < fitchangetol) {
            break;
        // }
    }
}

#endif
