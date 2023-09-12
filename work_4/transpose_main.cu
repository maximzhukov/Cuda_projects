// Made by Maxim Zhukov
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/extrema.h>
#include <iostream>
#include <fstream>
#include <string>
#include <iomanip>

using namespace std;
using namespace thrust;

const unsigned BLOCKS = 1024;
const unsigned THREADS = 1024;

#define __TIME_COUNT__

struct abs_functor : public thrust::unary_function<double, double>{
    __host__ __device__
    double operator()(double elem) const {
        return elem < 0.0 ? -elem : elem;
    }
};


struct abs_comparator{
    abs_functor fabs;

    __host__ __device__ 
    double operator()(double a, double b){
        return fabs(a) < fabs(b);
    }
};


void throw_on_cuda_error(const cudaError_t& code, int itter){
    if(code != cudaSuccess){
        string err = cudaGetErrorString(code);
        err += ", on iteration: ";
        err += to_string(itter);
        throw runtime_error(err);
    }
}

__global__ void gauss_step_L(double* C, unsigned n, unsigned size, unsigned col, double max_elem){
    unsigned thrd_idx = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned thrd_step = blockDim.x * gridDim.x;

    //unsigned start_point = (col + 1) >> 8;
    unsigned index = thrd_idx + col + 1 - ((col + 1) & 255);
    unsigned idx0 = size * col;
    
    if(index > col && index < n){
        C[idx0 + index] /= max_elem;
    }

    for(index += thrd_step; index < n; index += thrd_step){
        C[idx0 + index] /= max_elem;
    }
}

__global__ void gauss_step_U(double* C, unsigned n, unsigned size, unsigned col){
    unsigned i_idx = threadIdx.x;
    unsigned j_idx = blockIdx.x;

    unsigned i_step = blockDim.x;
    unsigned j_step = gridDim.x;


    for(unsigned jndex = j_idx + col + 1; jndex < n; jndex += j_step){
        unsigned idx0 = jndex*size;
        double C_jc = C[idx0 + col];

        unsigned index = i_idx + col + 1 - ((col + 1) & 255); 

        if(index > col && index < n){
            //printf("[%d, %d] = %f\n", index, jndex, C[idx0 + index]);
            C[idx0 + index] -= C[size*col + index] * C_jc;
            //printf("[%d, %d] = %f\n", index, jndex, C[idx0 + index]);
        }
    
        for(index += i_step; index < n; index += i_step){
            C[idx0 + index] -= C[size*col + index] * C_jc;
        }
    }
}

__global__ void swap_lines(double* C, unsigned n, unsigned size, unsigned line1, unsigned line2){
    unsigned thrd_idx = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned thrd_step = blockDim.x * gridDim.x;

    //unsigned start_point = (col + 1) >> 8;
    for(unsigned index = thrd_idx; index < n; index += thrd_step){
        double temp = C[index*size + line1];
        C[index*size + line1] = C[index*size + line2];
        C[index*size + line2] = temp;
    }
}


unsigned get_allign_size(unsigned size){
    unsigned ans = size;
    // 256 = 2^8 =>
    unsigned modulo = size & 255;
    if(modulo){
        ans -= modulo;
        ans += 256;
    }
    return ans;
}

int main(){
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(nullptr);


    unsigned n;
    cin >> n;
    // alloc mem to union matrix(see wiki algorithm)
    unsigned size = get_allign_size(n);

    host_vector<double> h_C(size * n);
    device_vector<double> d_C;
    host_vector<unsigned> h_p(n);

    //host_vector<unsigned> h_p(n);
    //device_vector<unsigned> d_p(n);

    // input of matrix
    for(unsigned i = 0; i < n; ++i){
        h_p[i] = i; // init of permutation vector
        for(unsigned j = 0; j < n; ++j){
            cin >> h_C[j*size + i]; // we store need matrix in  transpose format here for easy thrust search
        }
    }

    // transporting mem to device:
    // memcpy host to device
    d_C = h_C;

    // pointers to mem:
    double* raw_C = thrust::raw_pointer_cast(d_C.data());
    //unsigned* raw_p = thrust::raw_pointer_cast(d_p.data());

    // compute  LU
    #ifdef __TIME_COUNT__
    cudaEvent_t start, stop;
    float gpu_time = 0.0;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    cudaEventRecord(start, 0);
    #endif

    try{
        for(unsigned i = 0; i < n - 1; ++i){
            // search index of max elem in col
            auto it_beg = d_C.begin() + i*size;


            auto max_elem = thrust::max_element(it_beg + i, it_beg + size, abs_comparator());

            unsigned max_idx = max_elem - it_beg;
            double max_val = *max_elem;

            if(max_idx != i){
                swap_lines<<<BLOCKS, THREADS>>>(raw_C, n, size, i, max_idx);
                h_p[i] = max_idx;
                cudaThreadSynchronize();
            }

            gauss_step_L<<<BLOCKS, THREADS>>>(raw_C, n, size, i, max_val);
            cudaThreadSynchronize();

            gauss_step_U<<<BLOCKS, THREADS>>>(raw_C, n, size, i);
            throw_on_cuda_error(cudaGetLastError(), i);
        }
    }catch(runtime_error& err){
        cout << "ERROR: " << err.what() << endl;
    }

    #ifdef __TIME_COUNT__
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&gpu_time, start, stop);

    // open log:
    ofstream log("logs.log", ios::app);
    log << "Fast transpose" << endl;
    // threads
    log << BLOCKS << endl;
    // size:
    log << n << endl;
    // time:
    log << gpu_time << endl;
    log.close();
    #endif

    

    // memcpy device to host
    h_C = d_C;

    #ifndef __TIME_COUNT__
    // output for matrix:
    cout << std::scientific << std::setprecision(10);
    for(unsigned i = 0; i < n; ++i){
        for(unsigned j = 0; j < n; ++j){
            cout << h_C[j*size + i] << " ";
        }
        cout << endl;
    }
    // output of vector
    for(unsigned i = 0; i < n; ++i){
        cout << h_p[i] << " ";
    }
    cout << endl;
    #endif

    return 0;
}
