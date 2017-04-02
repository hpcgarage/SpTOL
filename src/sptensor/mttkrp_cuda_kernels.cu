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
#include <cuda_runtime.h>


template <typename T>
__device__ static void print_array(const T array[], size_t length, T start_index) {
    if(length == 0) {
        return;
    }
    printf("%d", (int) (array[0] + start_index));
    size_t i;
    for(i = 1; i < length; ++i) {
        printf(", %d", (int) (array[i] + start_index));
    }
    printf("\n");
}


__device__ static void print_array(const sptScalar array[], size_t length, size_t start_index) {
    if(length == 0) {
        return;
    }
    printf("%.2f", array[0] + start_index);
    size_t i;
    for(i = 1; i < length; ++i) {
        printf(", %.2f", array[i] + start_index);
    }
    printf("\n");
}


__device__ void lock(int* mutex) {
  /* compare mutex to 0.
     when it equals 0, set it to 1
     we will break out of the loop after mutex gets set to  */
    while (atomicCAS(mutex, 0, 1) != 0) {
    /* do nothing */
    }
}


__device__ void unlock(int* mutex) {
    atomicExch(mutex, 0);
}





/* impl_num = 01 */
__global__ void spt_MTTKRPKernelNnz3D(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;
    const size_t x = (blockIdx.x + block_offset) * blockDim.x + tidx;

    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz) {
      size_t const mode_i = mode_ind[x];
      size_t times_mat_index = dev_mats_order[1];
      sptScalar * times_mat = dev_mats[times_mat_index];
      size_t * times_inds = Xinds[times_mat_index];
      size_t tmp_i = times_inds[x];
      sptScalar const entry = Xvals[x];
      size_t times_mat_index_2 = dev_mats_order[2];
      sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
      size_t * times_inds_2 = Xinds[times_mat_index_2];
      size_t tmp_i_2 = times_inds_2[x];
      sptScalar tmp_val = 0;
      for(size_t r=0; r<R; ++r) {
        tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
        atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
      }

    }
   __syncthreads();

}


/* impl_num = 02 */
__global__ void spt_MTTKRPKernelNnzRank3D(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;
    const size_t tidy = threadIdx.y;
    const size_t x = (blockIdx.x + block_offset) * blockDim.x + tidx;
    // printf("x: %lu, tidx: %lu, tidy: %lu\n", x, tidx, tidy);

    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz && tidy < R) {
      size_t const mode_i = mode_ind[x];
      size_t times_mat_index = dev_mats_order[1];
      sptScalar * times_mat = dev_mats[times_mat_index];
      size_t * times_inds = Xinds[times_mat_index];
      size_t tmp_i = times_inds[x];
      sptScalar const entry = Xvals[x];
      size_t times_mat_index_2 = dev_mats_order[2];
      sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
      size_t * times_inds_2 = Xinds[times_mat_index_2];
      size_t tmp_i_2 = times_inds_2[x];
      sptScalar tmp_val = 0;

      tmp_val = entry * times_mat[tmp_i * stride + tidy] * times_mat_2[tmp_i_2 * stride + tidy];
      // printf("x: %lu, tidy: %lu, tmp_val: %lf\n", x, tidy, tmp_val);
      atomicAdd(&(mvals[mode_i * stride + tidy]), tmp_val);      
    }
   __syncthreads();

}


/* impl_num = 03 */
__global__ void spt_MTTKRPKernelNnzRankSplit3D(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;
    const size_t tidy = threadIdx.y;
    const size_t x = (blockIdx.x + block_offset) * blockDim.x + tidx;
    const size_t rank_size = R / blockDim.y;  // R is dividable to blockDim.y

    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz && tidy * rank_size < R) {
      size_t const mode_i = mode_ind[x];
      size_t times_mat_index = dev_mats_order[1];
      sptScalar * times_mat = dev_mats[times_mat_index];
      size_t * times_inds = Xinds[times_mat_index];
      size_t tmp_i = times_inds[x];
      sptScalar const entry = Xvals[x];
      size_t times_mat_index_2 = dev_mats_order[2];
      sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
      size_t * times_inds_2 = Xinds[times_mat_index_2];
      size_t tmp_i_2 = times_inds_2[x];
      sptScalar tmp_val = 0;

      for(size_t r=tidy*rank_size; r<(tidy+1)*rank_size; ++r) {
        tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
        atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
      }

    }
   __syncthreads();

}


/* impl_num = 04 */
__global__ void spt_MTTKRPKernelRankNnz3D(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t x = (blockIdx.x + block_offset) * blockDim.y + tidy;

    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz && tidx < R) {
      size_t const mode_i = mode_ind[x];
      size_t times_mat_index = dev_mats_order[1];
      sptScalar * times_mat = dev_mats[times_mat_index];
      size_t * times_inds = Xinds[times_mat_index];
      size_t tmp_i = times_inds[x];
      sptScalar const entry = Xvals[x];
      size_t times_mat_index_2 = dev_mats_order[2];
      sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
      size_t * times_inds_2 = Xinds[times_mat_index_2];
      size_t tmp_i_2 = times_inds_2[x];
      sptScalar tmp_val = 0;

      tmp_val = entry * times_mat[tmp_i * stride + tidx] * times_mat_2[tmp_i_2 * stride + tidx];
      atomicAdd(&(mvals[mode_i * stride + tidx]), tmp_val);      
    }
   __syncthreads();

}


/* impl_num = 05 */
__global__ void spt_MTTKRPKernelRankSplitNnz3D(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t x = (blockIdx.x + block_offset) * blockDim.y + tidy;
    const size_t num_loops = R / blockDim.x;
    const size_t rest_loop = R - num_loops * blockDim.x;


    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz) {
        size_t const mode_i = mode_ind[x];
        size_t times_mat_index = dev_mats_order[1];
        sptScalar * times_mat = dev_mats[times_mat_index];
        size_t * times_inds = Xinds[times_mat_index];
        size_t tmp_i = times_inds[x];
        sptScalar const entry = Xvals[x];
        size_t times_mat_index_2 = dev_mats_order[2];
        sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
        size_t * times_inds_2 = Xinds[times_mat_index_2];
        size_t tmp_i_2 = times_inds_2[x];
        sptScalar tmp_val = 0;
        size_t r;

        for(size_t l=0; l<num_loops; ++l) {
            r = tidx + l * blockDim.x;
            tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
            atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
            __syncthreads();
        }

        if(rest_loop > 0 && tidx < rest_loop) {
            r = tidx + num_loops * blockDim.x;
            tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
            atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
            __syncthreads();
        }
    }
   

}


/* impl_num = 09 */
__global__ void spt_MTTKRPKernelScratch(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    sptScalar * dev_scratch,
    size_t block_offset
) {
    const size_t tidx = threadIdx.x;
    const size_t x = (blockIdx.x + block_offset) * blockDim.x + tidx;

    size_t const * const mode_ind = Xinds[mode];
    /* The 64-bit floating-point version of atomicAdd() is only supported by devices of compute capability 6.x and higher. */
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];

    if(x < nnz) {
      size_t times_mat_index = dev_mats_order[1];
      sptScalar * times_mat = dev_mats[times_mat_index];
      size_t * times_inds = Xinds[times_mat_index];
      size_t tmp_i = times_inds[x];
      sptScalar const entry = Xvals[x];
      for(size_t r=0; r<R; ++r) {
        dev_scratch[x * stride + r] = entry * times_mat[tmp_i * stride + r];
      }

      for(size_t i=2; i<nmodes; ++i) {
        times_mat_index = dev_mats_order[i];
        times_mat = dev_mats[times_mat_index];
        times_inds = Xinds[times_mat_index];
        tmp_i = times_inds[x];
        for(size_t r=0; r<R; ++r) {
          dev_scratch[x * stride + r] *= times_mat[tmp_i * stride + r];
        }
      }

    }
   __syncthreads();

    if(x < nnz) {
      size_t const mode_i = mode_ind[x];
      // printf("x: %lu, mode_i: %lu\n", x, mode_i);
      for(size_t r=0; r<R; ++r) {
        atomicAdd(&(mvals[mode_i * stride + r]), dev_scratch[x * stride + r]);
      }
    }
   __syncthreads();

}


/* impl_num = 11. */
__global__ void spt_MTTKRPKernelBlockNnz3D(
    const size_t mode,
    const size_t nmodes,
    const size_t * nnz,
    const size_t * dev_nnz_blk_begin,
    const size_t R,
    const size_t stride,
    size_t * const inds_low_allblocks,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats
) {
    const size_t tidx = threadIdx.x;
    const size_t bidx = blockIdx.x;
    size_t x;
    // if(tidx == 0 && bidx == 0)
    //     printf("Execute spt_MTTKRPKernelBlockNnz3D kernel.\n");

    /* block range */
    const size_t nnz_blk = nnz[bidx];
    const size_t nnz_blk_begin = dev_nnz_blk_begin[bidx];
    size_t num_loops_nnz = 1;
    if(nnz_blk > blockDim.x) {
        num_loops_nnz = (nnz_blk + blockDim.x - 1) / blockDim.x;
    }
    // if(tidx == 0)
    //     printf("bidx: %lu, nnz_blk: %lu, nnz_blk_begin: %lu\n", bidx, nnz_blk, nnz_blk_begin);

    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = tidx + nl * blockDim.x;
        if(x < nnz_blk) {
            size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_allblocks[mode];    // local base
            // printf("[x: %lu, bidx: %lu] global: %lu, mode_i: %lu\n", x, bidx, mode_ind[x + nnz_blk_begin], mode_i);
            size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index];  // local base
            sptScalar const entry = Xvals[x + nnz_blk_begin];
            size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index_2];  // local base
            sptScalar tmp_val = 0;
            // printf("[x: %lu, bidx: %lu] nnz_blk_begin: %lu, mode_ind[x + nnz_blk_begin]: %lu, mode_i: %lu, entry: %.2f, tmp_i: %lu, 1st: %.2f, tmp_i_2: %lu, 2nd: %.2f\n", x, bidx, nnz_blk_begin, mode_ind[x + nnz_blk_begin], mode_i, entry, tmp_i, times_mat[tmp_i * stride + 0], tmp_i_2, times_mat_2[tmp_i_2 * stride + 0]);
            for(size_t r=0; r<R; ++r) {
            tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
            atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
            }

            __syncthreads();
        }
    }   // End loop nl

}



/* impl_num = 15 */
__global__ void spt_MTTKRPKernelBlockRankSplitNnz3D(
    const size_t mode,
    const size_t nmodes,
    const size_t * nnz,
    const size_t * dev_nnz_blk_begin,
    const size_t R,
    const size_t stride,
    size_t * const inds_low_allblocks,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats
) {
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t bidx = blockIdx.x; // index block, also nnz
    size_t x;
    const size_t num_loops_r = R / blockDim.x;
    const size_t rest_loop = R - num_loops_r * blockDim.x;
    // if(tidx == 0 && bidx == 0)
    //     printf("Execute spt_MTTKRPKernelBlockRankSplitNnz3D kernel.\n");
    

    /* block range */
    const size_t nnz_blk = nnz[bidx];
    const size_t nnz_blk_begin = dev_nnz_blk_begin[bidx];
    size_t num_loops_nnz = 1;
    if(nnz_blk > blockDim.y) {
        num_loops_nnz = (nnz_blk + blockDim.y - 1) / blockDim.y;
    }
    // if(tidy == 0)
    //     printf("bidx: %lu, nnz_blk: %lu, nnz_blk_begin: %lu\n", bidx, nnz_blk, nnz_blk_begin);

    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = tidy + nl * blockDim.y;
        if(x < nnz_blk) {
            size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_allblocks[mode];    // local base
            // printf("[x: %lu, bidx: %lu] global: %lu, mode_i: %lu\n", x, bidx, mode_ind[x + nnz_blk_begin], mode_i);
            size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index];  // local base
            sptScalar const entry = Xvals[x + nnz_blk_begin];
            size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index_2];  // local base
            sptScalar tmp_val = 0;
            size_t r;
            // if(tidx == 0)
            // printf("[x: %lu, bidx: %lu] nnz_blk_begin: %lu, mode_ind[tidx + nnz_blk_begin]: %lu, mode_i: %lu, entry: %.2f, tmp_i: %lu, 1st: %.2f, tmp_i_2: %lu, 2nd: %.2f\n", x, bidx, nnz_blk_begin, mode_ind[x + nnz_blk_begin], mode_i, entry, tmp_i, times_mat[tmp_i * stride + 0], tmp_i_2, times_mat_2[tmp_i_2 * stride + 0]);

            for(size_t l=0; l<num_loops_r; ++l) {
                r = tidx + l * blockDim.x;
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
                atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
            }

            if(rest_loop > 0 && tidx < rest_loop) {
                r = tidx + num_loops_r * blockDim.x;
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r]; 
                atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
            }
            __syncthreads();
        }
    }




}



/* impl_num = 16 */
__global__ void spt_MTTKRPKernelBlockRankSplitNnz3D_SMCoarse(
    const size_t mode,
    const size_t nmodes,
    const size_t * nnz,
    const size_t * dev_nnz_blk_begin,
    const size_t R,
    const size_t stride,
    size_t * const inds_low_allblocks,
    size_t ** const inds_low,
    size_t ** const Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats) 
{
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t bidx = blockIdx.x; // index block, also nnz
    size_t x;
    const size_t num_loops_r = R / blockDim.x;
    const size_t rest_loop = R - num_loops_r * blockDim.x;
    size_t r;
    extern __shared__ sptScalar mem_pool[];
    // clock_t start_tick, end_tick;
    // double elapsed_time;
    // double g2s_time = 0, comp_time = 0, s2g_time = 0;

    /* block range */
    const size_t nnz_blk = nnz[bidx];
    const size_t nnz_blk_begin = dev_nnz_blk_begin[bidx];
    const size_t inds_low_mode = inds_low[bidx][mode];
    const size_t Xndims_blk_mode = Xndims[bidx][mode];
    size_t num_loops_nnz = 1;
    if(nnz_blk > blockDim.y) {
        num_loops_nnz = (nnz_blk + blockDim.y - 1) / blockDim.y;
    }
    size_t num_loops_blk_mode = 1;
    if(Xndims_blk_mode > blockDim.y) {
        num_loops_blk_mode = (Xndims_blk_mode + blockDim.y - 1) / blockDim.y;
    }
    size_t sx;

    sptScalar * const shr_mvals = (sptScalar *) mem_pool; // size A nrows * stride 

    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    /* Use registers to avoid repeated memory accesses */
    size_t const inds_low_allblocks_mode = inds_low_allblocks[mode];

    for(size_t l=0; l<num_loops_r; ++l) {
        r = tidx + l * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_mode; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_mode) {
                shr_mvals[sx * stride + r] = 0;
            }
            __syncthreads();
        }        
    }
    if(rest_loop > 0 && tidx < rest_loop) {
        r = tidx + num_loops_r * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_mode; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_mode) {
                shr_mvals[sx * stride + r] = 0;
            }
            __syncthreads();
        }
    }

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = tidy + nl * blockDim.y;
        if(x < nnz_blk) {
            size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_mode;    // local base for block
            size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index];  // local base
            sptScalar const entry = Xvals[x + nnz_blk_begin];
            size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_allblocks[times_mat_index_2];  // local base
            sptScalar tmp_val = 0;
            // printf("[x: %lu, bidx: %lu] entry: %f, 1st: %f, 2nd: %f\n", x, bidx, entry, times_mat[tmp_i * stride + 0], times_mat_2[tmp_i_2 * stride + 0]);

            for(size_t l=0; l<num_loops_r; ++l) {
                r = tidx + l * blockDim.x;

                // start_tick = clock();
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
                atomicAdd(&(shr_mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
                // elapsed_time = (clock() - start_tick)/0.82e9;
                // comp_time += elapsed_time;

            } // End loop l

            if(rest_loop > 0 && tidx < rest_loop) {
                r = tidx + num_loops_r * blockDim.x;

                // start_tick = clock();
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r]; 
                atomicAdd(&(shr_mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
                // elapsed_time = (clock() - start_tick)/0.82e9;
                // comp_time += elapsed_time;
            } // End rest_loop
          __syncthreads();
        }   // End if(x < nnz_blk)
    }   // End loop nl


    for(size_t l=0; l<num_loops_r; ++l) {
        r = tidx + l * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_mode; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_mode) {
                atomicAdd(&(mvals[(sx + inds_low_mode - inds_low_allblocks_mode) * stride + r]), shr_mvals[sx * stride + r]);
            }
            __syncthreads();
        }
    }
    if(rest_loop > 0 && tidx < rest_loop) {
        r = tidx + num_loops_r * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_mode; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_mode) {
                atomicAdd(&(mvals[(sx + inds_low_mode - inds_low_allblocks_mode) * stride + r]), shr_mvals[sx * stride + r]);
            }
            __syncthreads();
        }
    }

    // printf("(%u, <%u, %u>)  g2s_time: %lf, comp_time: %lf, s2g_time: %lf\n", bidx, tidx, tidy, g2s_time, comp_time, s2g_time);
}




/* impl_num = 17 */
__global__ void spt_MTTKRPKernelBlockRankSplitNnz3D_SMMedium(
    const size_t mode,
    const size_t nmodes,
    const size_t * nnz,
    const size_t * dev_nnz_blk_begin,
    const size_t R,
    const size_t stride,
    size_t * const inds_low_allblocks,
    size_t ** const inds_low,
    size_t ** const Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats) 
{
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t bidx = blockIdx.x; // index block, also nnz
    size_t x;
    const size_t num_loops_r = R / blockDim.x;
    const size_t rest_loop = R - num_loops_r * blockDim.x;
    size_t r;
    extern __shared__ sptScalar mem_pool[];

    /* block range */
    const size_t nnz_blk = nnz[bidx];
    const size_t nnz_blk_begin = dev_nnz_blk_begin[bidx];
    size_t * const inds_low_blk = inds_low[bidx];
    size_t * const Xndims_blk = Xndims[bidx];
    size_t num_loops_nnz = 1;
    if(nnz_blk > blockDim.y) {
        num_loops_nnz = (nnz_blk + blockDim.y - 1) / blockDim.y;
    }   


    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    /* Use registers to avoid repeated memory accesses */
    size_t const inds_low_blk_A = inds_low_blk[mode];
    size_t const inds_low_blk_B = inds_low_blk[times_mat_index];
    size_t const inds_low_blk_C = inds_low_blk[times_mat_index_2];
    size_t const inds_low_allblocks_A = inds_low_allblocks[mode];
    size_t const inds_low_allblocks_B = inds_low_allblocks[times_mat_index];
    size_t const inds_low_allblocks_C = inds_low_allblocks[times_mat_index_2];
    size_t const Xndims_blk_A = Xndims_blk[mode];
    size_t const Xndims_blk_B = Xndims_blk[times_mat_index];
    size_t const Xndims_blk_C = Xndims_blk[times_mat_index_2];

    size_t num_loops_blk_A = 1;
    if(Xndims_blk_A > blockDim.y) {
        num_loops_blk_A = (Xndims_blk_A + blockDim.y - 1) / blockDim.y;
    }
    size_t num_loops_blk_B = 1;
    if(Xndims_blk_B > blockDim.y) {
        num_loops_blk_B = (Xndims_blk_B + blockDim.y - 1) / blockDim.y;
    }
    size_t num_loops_blk_C = 1;
    if(Xndims_blk_C > blockDim.y) {
        num_loops_blk_C = (Xndims_blk_C + blockDim.y - 1) / blockDim.y;
    }   
    size_t sx;


    // if(tidx == 0 && tidy == 0)
    //     printf("[%lu, (%lu, %lu)]  (Xndims_blk_A: %lu, Xndims_blk_B: %lu, Xndims_blk_C: %lu); (inds_low_blk_A: %lu, inds_low_blk_B: %lu, inds_low_blk_C: %lu); (inds_low_allblocks_A: %lu, inds_low_allblocks_B: %lu, inds_low_allblocks_C: %lu)\n", bidx, tidx, tidy, Xndims_blk_A, Xndims_blk_B, Xndims_blk_C, inds_low_blk_A, inds_low_blk_B, inds_low_blk_C, inds_low_allblocks_A, inds_low_allblocks_B, inds_low_allblocks_C);


    sptScalar * const shrA = (sptScalar *) mem_pool; // A: size nrows * stride
    sptScalar * const shrB = (sptScalar *) (shrA + Xndims_blk_A * stride); // B: size nrows * stride
    sptScalar * const shrC = (sptScalar *) (shrB + Xndims_blk_B * stride); // C: size nrows * stride

    for(size_t l=0; l<num_loops_r; ++l) {
        r = tidx + l * blockDim.x;
        /* Set shrA = 0 */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                shrA[sx * stride + r] = 0;
            }
            __syncthreads();
        }
        /* Load shrB */
        for(size_t sl=0; sl<num_loops_blk_B; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_B) {
                shrB[sx * stride + r] = times_mat[(sx + inds_low_blk_B - inds_low_allblocks_B) * stride + r];
            }
            __syncthreads();
        }
        /* Load shrC */
        for(size_t sl=0; sl<num_loops_blk_C; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_C) {
                shrC[sx * stride + r] = times_mat_2[(sx + inds_low_blk_C - inds_low_allblocks_C) * stride + r];
            }
            __syncthreads();
        }

    }   // End loop l: num_loops_r

    if(rest_loop > 0 && tidx < rest_loop) {
        r = tidx + num_loops_r * blockDim.x;
        /* Set shrA = 0 */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                shrA[sx * stride + r] = 0;
            }
            __syncthreads();
        }
        /* Load shrB */
        for(size_t sl=0; sl<num_loops_blk_B; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_B) {
                shrB[sx * stride + r] = times_mat[(sx + inds_low_blk_B - inds_low_allblocks_B) * stride + r];
            }
            __syncthreads();
        }
        /* Load shrC */
        for(size_t sl=0; sl<num_loops_blk_C; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_C) {
                shrC[sx * stride + r] = times_mat_2[(sx + inds_low_blk_C - inds_low_allblocks_C) * stride + r];
            }
            __syncthreads();
        }
    }

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = tidy + nl * blockDim.y;
        if(x < nnz_blk) {
            size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_blk_A;    // local base for block
            // printf("[x: %lu, bidx: %lu] global: %lu, mode_i: %lu\n", x, bidx, mode_ind[x + nnz_blk_begin], mode_i);
            size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_blk_B;  // local base
            sptScalar const entry = Xvals[x + nnz_blk_begin];
            size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_blk_C;  // local base
            sptScalar tmp_val = 0;

            for(size_t l=0; l<num_loops_r; ++l) {
                r = tidx + l * blockDim.x;            
                // if(tidx == 0)
                //     printf("[%lu, (0, %lu)]  nnz_blk_begin: %lu, mode_ind[tidy + nnz_blk_begin]: %lu, mode_i: %lu, entry: %.2f, tmp_i: %lu, 1st: %.2f, tmp_i_2: %lu, 2nd: %.2f\n", bidx, tidy, nnz_blk_begin, mode_ind[tidy + nnz_blk_begin], mode_i, entry, tmp_i, shrB[tmp_i * stride + 0], tmp_i_2, shrC[tmp_i_2 * stride + 0]);

                tmp_val = entry * shrB[tmp_i * stride + r] * shrC[tmp_i_2 * stride + r];
                atomicAdd(&(shrA[mode_i * stride + r]), tmp_val);
                __syncthreads();
            } // End loop l: num_loops_r

            if(rest_loop > 0 && tidx < rest_loop) {
                r = tidx + num_loops_r * blockDim.x;

                tmp_val = entry * shrB[tmp_i * stride + r] * shrC[tmp_i_2 * stride + r];
                atomicAdd(&(shrA[mode_i * stride + r]), tmp_val);
                __syncthreads();
            } // End if rest_loop
        }   // End if(x < nnz_blk)

    }   // End loop nl: num_loops_nnz

    /* Store back shrA */
    for(size_t l=0; l<num_loops_r; ++l) {
        r = tidx + l * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                atomicAdd(&(mvals[(sx + inds_low_blk_A - inds_low_allblocks_A) * stride + r]), shrA[sx * stride + r]);
                // __syncthreads();
                // if(tidx == 0)
                //     printf("[%lu, (0, %lu)] sx: %lu, sx + inds_low_blk_A - inds_low_allblocks_A: %lu, mvals: %lf\n", bidx, tidy, sx, sx + inds_low_blk_A - inds_low_allblocks_A, mvals[(sx + inds_low_blk_A - inds_low_allblocks_A) * stride + 0]);
            }
            __syncthreads();
        }
    }
    if(rest_loop > 0 && tidx < rest_loop) {
        r = tidx + num_loops_r * blockDim.x;
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                atomicAdd(&(mvals[(sx + inds_low_blk_A - inds_low_allblocks_A) * stride + r]), shrA[sx * stride + r]);
            }
            __syncthreads();
        }
    }

}




/* impl_num = 18 */
__global__ void spt_MTTKRPKernelBlockRankSplitNnz3D_SMMediumOpt(
    const size_t mode,
    const size_t nmodes,
    const size_t * nnz,
    const size_t * dev_nnz_blk_begin,
    const size_t R,
    const size_t stride,
    size_t * const inds_low_allblocks,
    size_t ** const inds_low,
    size_t ** const Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats) 
{
    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    const size_t bidx = blockIdx.x; // index block, also nnz
    size_t x;
    const size_t num_loops_r = R / blockDim.x;
    const size_t rest_loop = R - num_loops_r * blockDim.x;
    size_t r;
    extern __shared__ sptScalar mem_pool[];

    /* block range */
    const size_t nnz_blk = nnz[bidx];
    const size_t nnz_blk_begin = dev_nnz_blk_begin[bidx];
    size_t * const inds_low_blk = inds_low[bidx];
    size_t * const Xndims_blk = Xndims[bidx];
    size_t num_loops_nnz = 1;
    if(nnz_blk > blockDim.y) {
        num_loops_nnz = (nnz_blk + blockDim.y - 1) / blockDim.y;
    }   


    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    /* Use registers to avoid repeated memory accesses */
    size_t const inds_low_blk_A = inds_low_blk[mode];
    size_t const inds_low_blk_B = inds_low_blk[times_mat_index];
    size_t const inds_low_blk_C = inds_low_blk[times_mat_index_2];
    size_t const inds_low_allblocks_A = inds_low_allblocks[mode];
    size_t const inds_low_allblocks_B = inds_low_allblocks[times_mat_index];
    size_t const inds_low_allblocks_C = inds_low_allblocks[times_mat_index_2];
    size_t const Xndims_blk_A = Xndims_blk[mode];
    size_t const Xndims_blk_B = Xndims_blk[times_mat_index];
    size_t const Xndims_blk_C = Xndims_blk[times_mat_index_2];

    size_t num_loops_blk_A = 1;
    if(Xndims_blk_A > blockDim.y) {
        num_loops_blk_A = (Xndims_blk_A + blockDim.y - 1) / blockDim.y;
    }
    size_t num_loops_blk_B = 1;
    if(Xndims_blk_B > blockDim.y) {
        num_loops_blk_B = (Xndims_blk_B + blockDim.y - 1) / blockDim.y;
    }
    size_t num_loops_blk_C = 1;
    if(Xndims_blk_C > blockDim.y) {
        num_loops_blk_C = (Xndims_blk_C + blockDim.y - 1) / blockDim.y;
    }   
    size_t sx;


    // if(tidx == 0 && tidy == 0)
    //     printf("[%lu, (%lu, %lu)]  (Xndims_blk_A: %lu, Xndims_blk_B: %lu, Xndims_blk_C: %lu); (inds_low_blk_A: %lu, inds_low_blk_B: %lu, inds_low_blk_C: %lu); (inds_low_allblocks_A: %lu, inds_low_allblocks_B: %lu, inds_low_allblocks_C: %lu)\n", bidx, tidx, tidy, Xndims_blk_A, Xndims_blk_B, Xndims_blk_C, inds_low_blk_A, inds_low_blk_B, inds_low_blk_C, inds_low_allblocks_A, inds_low_allblocks_B, inds_low_allblocks_C);


    sptScalar * const shrA = (sptScalar *) mem_pool; // A: size nrows * stride
    sptScalar * const shrB = (sptScalar *) (shrA + Xndims_blk_A * stride); // B: size nrows * stride
    sptScalar * const shrC = (sptScalar *) (shrB + Xndims_blk_B * stride); // C: size nrows * stride

    for(size_t l=0; l<num_loops_r; ++l) {
        r = tidx + l * blockDim.x;
        /* Set shrA = 0 */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                shrA[sx * stride + tidx] = 0;
            }
            __syncthreads();
        }
        /* Load shrB */
        for(size_t sl=0; sl<num_loops_blk_B; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_B) {
                shrB[sx * stride + tidx] = times_mat[(sx + inds_low_blk_B - inds_low_allblocks_B) * stride + r];
            }
            __syncthreads();
        }
        /* Load shrC */
        for(size_t sl=0; sl<num_loops_blk_C; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_C) {
                shrC[sx * stride + tidx] = times_mat_2[(sx + inds_low_blk_C - inds_low_allblocks_C) * stride + r];
            }
            __syncthreads();
        }


        for(size_t nl=0; nl<num_loops_nnz; ++nl) {
            x = tidy + nl * blockDim.y;
            if(x < nnz_blk) {
                size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_blk_A;    // local base for block
                size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_blk_B;  // local base
                sptScalar const entry = Xvals[x + nnz_blk_begin];
                size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_blk_C;  // local base
                sptScalar tmp_val = 0;

                tmp_val = entry * shrB[tmp_i * stride + tidx] * shrC[tmp_i_2 * stride + tidx];
                atomicAdd(&(shrA[mode_i * stride + tidx]), tmp_val);
                __syncthreads();

            }
        }

        /* Store back shrA */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                atomicAdd(&(mvals[(sx + inds_low_blk_A - inds_low_allblocks_A) * stride + r]), shrA[sx * stride + tidx]);
            }
            __syncthreads();
        }

    }   // End loop l: num_loops_r

    if(rest_loop > 0 && tidx < rest_loop) {
        r = tidx + num_loops_r * blockDim.x;

        /* Set shrA = 0 */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                shrA[sx * stride + tidx] = 0;
            }
            __syncthreads();
        }
        /* Load shrB */
        for(size_t sl=0; sl<num_loops_blk_B; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_B) {
                shrB[sx * stride + tidx] = times_mat[(sx + inds_low_blk_B - inds_low_allblocks_B) * stride + r];
            }
            __syncthreads();
        }
        /* Load shrC */
        for(size_t sl=0; sl<num_loops_blk_C; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_C) {
                shrC[sx * stride + tidx] = times_mat_2[(sx + inds_low_blk_C - inds_low_allblocks_C) * stride + r];
            }
            __syncthreads();
        }


        for(size_t nl=0; nl<num_loops_nnz; ++nl) {
            x = tidy + nl * blockDim.y;
            if(x < nnz_blk) {
                size_t const mode_i = mode_ind[x + nnz_blk_begin] - inds_low_blk_A;    // local base for block
                size_t tmp_i = times_inds[x + nnz_blk_begin] - inds_low_blk_B;  // local base
                sptScalar const entry = Xvals[x + nnz_blk_begin];
                size_t tmp_i_2 = times_inds_2[x + nnz_blk_begin] - inds_low_blk_C;  // local base
                sptScalar tmp_val = 0;

                tmp_val = entry * shrB[tmp_i * stride + tidx] * shrC[tmp_i_2 * stride + tidx];
                atomicAdd(&(shrA[mode_i * stride + tidx]), tmp_val);
                __syncthreads();

            }
        }


        /* Store back shrA */
        for(size_t sl=0; sl<num_loops_blk_A; ++sl) {
            sx = tidy + sl * blockDim.y;
            if(sx < Xndims_blk_A) {
                atomicAdd(&(mvals[(sx + inds_low_blk_A - inds_low_allblocks_A) * stride + r]), shrA[sx * stride + tidx]);
            }
            __syncthreads();
        }
    }   // End if rest_loop

}






/* impl_num = 29 */
__global__ void spt_MTTKRPKernelScratchDist(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    const size_t * inds_low,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats,
    sptScalar * dev_scratch
) {
    const size_t tidx = threadIdx.x;
    const size_t x = blockIdx.x * blockDim.x + tidx;

    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = dev_mats[nmodes];

    // if(x == 0) {
    //     printf("mvals:\n");
    //     for(size_t i=0; i<Xndims[mode]; ++i) {
    //         printf("%lf\n", mvals[i * stride]);
    //     }
    //     printf("mvals end\n");
    // }

    if(x < nnz) {
        size_t times_mat_index = dev_mats_order[1];
        sptScalar * times_mat = dev_mats[times_mat_index];
        size_t * times_inds = Xinds[times_mat_index];
        size_t tmp_i = times_inds[x] - inds_low[times_mat_index];
        sptScalar const entry = Xvals[x];
        for(size_t r=0; r<R; ++r) {
            dev_scratch[x * stride + r] = entry * times_mat[tmp_i * stride + r];
        }

        for(size_t i=2; i<nmodes; ++i) {
            times_mat_index = dev_mats_order[i];
            times_mat = dev_mats[times_mat_index];
            times_inds = Xinds[times_mat_index];
            tmp_i = times_inds[x] - inds_low[times_mat_index];
            for(size_t r=0; r<R; ++r) {
                dev_scratch[x * stride + r] *= times_mat[tmp_i * stride + r];
            }
        }

    }

    __syncthreads();

    if(x < nnz) {
        size_t const mode_i = mode_ind[x] - inds_low[mode];
        // printf("x: %lu, mode_ind[x]: %lu, mode_i: %lu\n", x, mode_ind[x], mode_i);
        for(size_t r=0; r<R; ++r) {
            atomicAdd(&(mvals[mode_i * stride + r]), dev_scratch[x * stride + r]);
        }
    }
    __syncthreads();

    // if(x == 0) {
    //     printf("inds_low[mode]: %lu, Xndims[mode]: %lu\n", inds_low[mode], Xndims[mode]);
    //     printf("nnz: %lu\n", nnz);;
    //     printf("mvals:\n");
    //     for(size_t i=0; i<Xndims[mode]; ++i) {
    //         printf("%lf\n", mvals[i * stride]);
    //     }
    //     printf("mvals end\n");
    // }
    
}



/* impl_num = 31 */
__global__ void spt_MTTKRPKernelNnz3DOneKernel(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats) 
{
    size_t num_loops_nnz = 1;
    size_t const nnz_per_loop = gridDim.x * blockDim.x;
    if(nnz > nnz_per_loop) {
        num_loops_nnz = (nnz + nnz_per_loop - 1) / nnz_per_loop;
    }


    const size_t tidx = threadIdx.x;
    size_t x;

    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = blockIdx.x * blockDim.x + tidx + nl * nnz_per_loop;
        if(x < nnz) {
            size_t const mode_i = mode_ind[x];
            size_t tmp_i = times_inds[x];
            sptScalar const entry = Xvals[x];
            size_t tmp_i_2 = times_inds_2[x];
            sptScalar tmp_val = 0;
            for(size_t r=0; r<R; ++r) {
            tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
            atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
            }
            __syncthreads();
        }
    }  

}


/* impl_num = 35 */
__global__ void spt_MTTKRPKernelRankSplitNnz3DOneKernel(
    const size_t mode,
    const size_t nmodes,
    const size_t nnz,
    const size_t R,
    const size_t stride,
    const size_t * Xndims,
    size_t ** const Xinds,
    const sptScalar * Xvals,
    const size_t * dev_mats_order,
    sptScalar ** dev_mats)
{
    size_t num_loops_nnz = 1;
    size_t const nnz_per_loop = gridDim.x * blockDim.y;
    if(nnz > nnz_per_loop) {
        num_loops_nnz = (nnz + nnz_per_loop - 1) / nnz_per_loop;
    }

    const size_t tidx = threadIdx.x;  // index rank
    const size_t tidy = threadIdx.y;  // index nnz
    size_t x;
    const size_t num_loops_r = R / blockDim.x;
    const size_t rest_loop = R - num_loops_r * blockDim.x;


    size_t const * const mode_ind = Xinds[mode];
    sptScalar * const mvals = (sptScalar*)dev_mats[nmodes];
    size_t times_mat_index = dev_mats_order[1];
    sptScalar * times_mat = dev_mats[times_mat_index];
    size_t * times_inds = Xinds[times_mat_index];
    size_t times_mat_index_2 = dev_mats_order[2];
    sptScalar * times_mat_2 = dev_mats[times_mat_index_2];
    size_t * times_inds_2 = Xinds[times_mat_index_2];

    for(size_t nl=0; nl<num_loops_nnz; ++nl) {
        x = blockIdx.x * blockDim.y + tidy + nl * nnz_per_loop;
        if(x < nnz) {
            size_t const mode_i = mode_ind[x];
            size_t tmp_i = times_inds[x];
            sptScalar const entry = Xvals[x];
            size_t tmp_i_2 = times_inds_2[x];
            sptScalar tmp_val = 0;
            size_t r;

            for(size_t l=0; l<num_loops_r; ++l) {
                r = tidx + l * blockDim.x;
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
                atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
            }

            if(rest_loop > 0 && tidx < rest_loop) {
                r = tidx + num_loops_r * blockDim.x;
                tmp_val = entry * times_mat[tmp_i * stride + r] * times_mat_2[tmp_i_2 * stride + r];
                atomicAdd(&(mvals[mode_i * stride + r]), tmp_val);
                __syncthreads();
            }
            __syncthreads();
        }
   
    }

}

