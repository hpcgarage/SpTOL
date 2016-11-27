/*
    This file is part of SpTOL.

    SpTOL is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    SpTOL is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with SpTOL.
    If not, see <http://www.gnu.org/licenses/>.
*/

#include <SpTOL.h>
#include <stdio.h>
#include <stdlib.h>
#include "matrix.h"
#include "mex.h"
#include "sptmx.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    spt_mxCheckArgs("sptDumpVector", 0, "No", 2, "Two");

    sptVector *vec = spt_mxGetPointer(prhs[0], 0);
    char *fn = mxArrayToString(prhs[1]);
    FILE *fp = fopen(fn, "w");
    mxFree(fn);
    if(!fp) {
        mexErrMsgIdAndTxt("SpTOL:sptDumpVector", "Cannot open file.");
    }

    int result = sptDumpVector(vec, fp);
    fclose(fp);
}
