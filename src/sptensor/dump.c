#include <SpTOL.h>
#include <stdio.h>

int sptDumpSparseTensor(const sptSparseTensor *tsr, size_t start_index, FILE *fp) {
    int iores;
    size_t mode, i;
    iores = fprintf(fp, "%zu\n", tsr->nmodes);
    if(iores < 0) {
        return -1;
    }
    for(mode = 0; mode < tsr->nmodes; ++mode) {
        if(mode != 0) {
            iores = fputs(" ", fp);
            if(iores < 0) {
                return -1;
            }
        }
        iores = fprintf(fp, "%zu", tsr->ndims[mode]);
        if(iores < 0) {
            return -1;
        }
    }
    fputs("\n", fp);
    for(i = 0; i < tsr->nnz; ++i) {
        for(mode = 0; mode < tsr->nmodes; ++mode) {
            iores = fprintf(fp, "%zu\t", tsr->inds[mode].data[i]+start_index);
            if(iores < 0) {
                return -1;
            }
        }
        iores = fprintf(fp, "%lf\n", (double) tsr->values.data[i]);
        if(iores < 0) {
            return -1;
        }
    }
    return 0;
}
