/******************************************************************************
 * Copyright (c) 2011, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2013, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/******************************************************************************
 * Test of iterator utilities
 ******************************************************************************/

// Ensure printing of CUDA runtime errors to console
#define CUB_STDERR

#include <iterator>
#include <stdio.h>

#include <cub/util_type.cuh>
#include <cub/util_allocator.cuh>
#include <cub/util_iterator.cuh>

#include "test_util.h"

using namespace cub;


//---------------------------------------------------------------------
// Globals, constants and typedefs
//---------------------------------------------------------------------

bool                    g_verbose = false;
CachingDeviceAllocator  g_allocator(true);


//---------------------------------------------------------------------
// Test kernels
//---------------------------------------------------------------------

/**
 * Test random access input iterator
 */
template <
    typename InputIteratorRA,
    typename T>
__global__ void Kernel(
    InputIteratorRA     d_in,
    T                   d_out,
    InputIteratorRA     *d_itrs)
{
    d_out[0] = *d_in;               // Value at offset 0
    d_out[1] = d_in[100];           // Value at offset 100
    d_out[2] = *(d_in + 1000);      // Value at offset 1000
    d_out[3] = *(&(d_in[10000]));   // Value at offset 10000

    d_in++;
    d_out[4] = d_in[0];             // Value at offset 1

    d_in += 20;
    d_out[5] = d_in[0];             // Value at offset 21
    d_itrs[0] = d_in;               // Iterator at offset 21

    d_in -= 10;
    d_out[6] = d_in[0];             // Value at offset 11;

    d_in -= 11;
    d_out[7] = d_in[0];             // Value at offset 0
    d_itrs[1] = d_in;               // Iterator at offset 0
}



//---------------------------------------------------------------------
// Host testing subroutines
//---------------------------------------------------------------------


/**
 * Run iterator test on device
 */
template <
    typename    InputIteratorRA,
    typename    T,
    int         TEST_VALUES>
void Test(
    InputIteratorRA     d_in,
    T                   (&h_reference)[TEST_VALUES])
{
    // Allocate device arrays
    T                   *d_out = NULL;
    InputIteratorRA     *d_itrs = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_out, sizeof(T) * TEST_VALUES));
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_itrs, sizeof(InputIteratorRA) * 2));

    int compare;

    // Run unguarded kernel
    Kernel<<<1, 1>>>(d_in, d_out, d_itrs);
    CubDebugExit(cudaDeviceSynchronize());

    // Check results
    compare = CompareDeviceResults(h_reference, d_out, TEST_VALUES, g_verbose, g_verbose);
    printf("\tValues: %s\n", (compare) ? "FAIL" : "PASS");
    AssertEquals(0, compare);

    // Check iterator at offset 21
    InputIteratorRA h_itr = d_in + 21;
    compare = CompareDeviceResults(&h_itr, d_itrs, 1, g_verbose, g_verbose);
    printf("\tIterators: %s\n", (compare) ? "FAIL" : "PASS");
    AssertEquals(0, compare);

    // Check iterator at offset 0
    compare = CompareDeviceResults(&d_in, d_itrs + 1, 1, g_verbose, g_verbose);
    printf("\tIterators: %s\n", (compare) ? "FAIL" : "PASS");
    AssertEquals(0, compare);

    // Cleanup
    if (d_out) CubDebugExit(g_allocator.DeviceFree(d_out));
    if (d_itrs) CubDebugExit(g_allocator.DeviceFree(d_itrs));
}


/**
 * Test constant iterator
 */
template <typename T>
void TestConstant(T base)
{
    T h_reference[8] = {base, base, base, base, base, base, base, base};

    Test(ConstantIteratorRA<T>(base), h_reference);
}


/**
 * Test counting iterator
 */
template <typename T>
void TestCounting(T base)
{
    // Initialize reference data
    T h_reference[8];
    h_reference[0] = base + 0;          // Value at offset 0
    h_reference[1] = base + 100;        // Value at offset 100
    h_reference[2] = base + 1000;       // Value at offset 1000
    h_reference[3] = base + 10000;      // Value at offset 10000
    h_reference[4] = base + 1;          // Value at offset 1
    h_reference[5] = base + 21;         // Value at offset 21
    h_reference[6] = base + 11;         // Value at offset 11
    h_reference[7] = base + 0;          // Value at offset 0;

    Test(ConstantIteratorRA<T>(base), h_reference);
}


/**
 * Test modified iterator
 */
template <typename T>
void TestModified()
{
    const unsigned int TEST_VALUES = 11000;

    T *h_data = malloc(sizeof(T) * TEST_VALUES);
    for (int i = 0; i < TEST_VALUES; ++i)
    {
        RandomBits(h_data[i]);
    }

    // Allocate device arrays
    T *d_data = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_data, sizeof(T) * TEST_VALUES));
    CubDebugExit(cudaMemcpy(d_data, h_data, sizeof(T) * TEST_VALUES, cudaMemcpyHostToDevice));

    // Initialize reference data
    T h_reference[8];
    h_reference[0] = h_data[0];          // Value at offset 0
    h_reference[1] = h_data[100];        // Value at offset 100
    h_reference[2] = h_data[1000];       // Value at offset 1000
    h_reference[3] = h_data[10000];      // Value at offset 10000
    h_reference[4] = h_data[1];          // Value at offset 1
    h_reference[5] = h_data[21];         // Value at offset 21
    h_reference[6] = h_data[11];         // Value at offset 11
    h_reference[7] = h_data[0];          // Value at offset 0;

    Test(CacheModifiedIteratorRA<LOAD_DEFAULT, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_CA, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_CG, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_CS, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_CV, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_LDG, T>(d_data), h_reference);
    Test(CacheModifiedIteratorRA<LOAD_VOLATILE, T>(d_data), h_reference);

    // Cleanup
    if (d_data) CubDebugExit(g_allocator.DeviceFree(d_data));
}


/**
 * Test transform iterator
 */
template <typename T>
void TestTransform()
{
    struct TransformOp
    {
        // Increment transform
        __host__ __device__ __forceinline__ T operator()(const T input)
        {
            T addend = 1;
            return input + addend;
        }
    };

    const unsigned int TEST_VALUES = 11000;

    T *h_data = malloc(sizeof(T) * TEST_VALUES);
    for (int i = 0; i < TEST_VALUES; ++i)
    {
        RandomBits(h_data[i]);
    }

    // Allocate device arrays
    T *d_data = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_data, sizeof(T) * TEST_VALUES));
    CubDebugExit(cudaMemcpy(d_data, h_data, sizeof(T) * TEST_VALUES, cudaMemcpyHostToDevice));

    TransformOp op;

    // Initialize reference data
    T h_reference[8];
    h_reference[0] = op(h_data[0]);          // Value at offset 0
    h_reference[1] = op(h_data[100]);        // Value at offset 100
    h_reference[2] = op(h_data[1000]);       // Value at offset 1000
    h_reference[3] = op(h_data[10000]);      // Value at offset 10000
    h_reference[4] = op(h_data[1]);          // Value at offset 1
    h_reference[5] = op(h_data[21]);         // Value at offset 21
    h_reference[6] = op(h_data[11]);         // Value at offset 11
    h_reference[7] = op(h_data[0]);          // Value at offset 0;

    Test(TransformIteratorRA<T, TransformOp, T*>(d_data, op), h_reference);

    // Cleanup
    if (d_data) CubDebugExit(g_allocator.DeviceFree(d_data));
}


/**
 * Test texture iterator
 */
template <typename T>
void TestTexture()
{
    const unsigned int TEST_VALUES = 11000;

    T *h_data = malloc(sizeof(T) * TEST_VALUES);
    for (int i = 0; i < TEST_VALUES; ++i)
    {
        RandomBits(h_data[i]);
    }

    // Allocate device arrays
    T *d_data = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_data, sizeof(T) * TEST_VALUES));
    CubDebugExit(cudaMemcpy(d_data, h_data, sizeof(T) * TEST_VALUES, cudaMemcpyHostToDevice));

    // Initialize reference data
    T h_reference[8];
    h_reference[0] = h_data[0];          // Value at offset 0
    h_reference[1] = h_data[100];        // Value at offset 100
    h_reference[2] = h_data[1000];       // Value at offset 1000
    h_reference[3] = h_data[10000];      // Value at offset 10000
    h_reference[4] = h_data[1];          // Value at offset 1
    h_reference[5] = h_data[21];         // Value at offset 21
    h_reference[6] = h_data[11];         // Value at offset 11
    h_reference[7] = h_data[0];          // Value at offset 0;

    // Create and bind iterator
    TexIteratorRA<T> d_itr;
    CubDebugExit(d_itr.BindTexture(d_data, sizeof(T) * TEST_VALUES));

    Test(d_itr, h_reference);

    // Cleanup
    CubDebugExit(d_itr.UnbindTexture());
    if (d_data) CubDebugExit(g_allocator.DeviceFree(d_data));
}


/**
 * Test texture transform iterator
 */
template <typename T>
void TestTexTransform()
{
    struct TransformOp
    {
        // Increment transform
        __host__ __device__ __forceinline__ T operator()(const T input)
        {
            T addend = 1;
            return input + addend;
        }
    };

    const unsigned int TEST_VALUES = 11000;

    T *h_data = malloc(sizeof(T) * TEST_VALUES);
    for (int i = 0; i < TEST_VALUES; ++i)
    {
        RandomBits(h_data[i]);
    }

    // Allocate device arrays
    T *d_data = NULL;
    CubDebugExit(g_allocator.DeviceAllocate((void**)&d_data, sizeof(T) * TEST_VALUES));
    CubDebugExit(cudaMemcpy(d_data, h_data, sizeof(T) * TEST_VALUES, cudaMemcpyHostToDevice));

    TransformOp op;

    // Initialize reference data
    T h_reference[8];
    h_reference[0] = op(h_data[0]);          // Value at offset 0
    h_reference[1] = op(h_data[100]);        // Value at offset 100
    h_reference[2] = op(h_data[1000]);       // Value at offset 1000
    h_reference[3] = op(h_data[10000]);      // Value at offset 10000
    h_reference[4] = op(h_data[1]);          // Value at offset 1
    h_reference[5] = op(h_data[21]);         // Value at offset 21
    h_reference[6] = op(h_data[11]);         // Value at offset 11
    h_reference[7] = op(h_data[0]);          // Value at offset 0;

    // Create and bind iterator
    TexTransformIteratorRA<T, TransformOp, T> d_itr;
    CubDebugExit(d_itr.BindTexture(d_data, sizeof(T) * TEST_VALUES));

    Test(d_itr, h_reference);

    // Cleanup
    CubDebugExit(d_itr.UnbindTexture());
    if (d_data) CubDebugExit(g_allocator.DeviceFree(d_data));
}



/**
 * Run non-integer tests
 */
template <typename T>
void TestInteger(Int2Type<false> is_integer)
{
    TestTransform<T>();
    TestTexture<T>();
    TestTexTransform<T>();
}

/**
 * Run integer tests
 */
template <typename T>
void TestInteger(Int2Type<true> is_integer)
{
    TestConstant<T>(0);
    TestConstant<T>(99);

    TestCounting<T>(0);
    TestCounting<T>(99);

    // Run non-integer tests
    TestInteger<T>(Int2Type<false>());
}

/**
 * Run tests
 */
template <typename T>
void Test()
{
    enum {
        IS_INTEGER = (Traits<T>::CATEGORY == SIGNED_INTEGER) || (Traits<T>::CATEGORY == UNSIGNED_INTEGER)
    };
    TestInteger<T>(Int2Type<IS_INTEGER>());
}


/**
 * Main
 */
int main(int argc, char** argv)
{
    // Initialize command line
    CommandLineArgs args(argc, argv);
    g_verbose = args.CheckCmdLineFlag("v");

    // Print usage
    if (args.CheckCmdLineFlag("help"))
    {
        printf("%s "
            "[--device=<device-id>] "
            "[--v] "
            "\n", argv[0]);
        exit(0);
    }

    // Initialize device
    CubDebugExit(args.DeviceInit());

    // Evaluate different data types
/*
    Test<char>();
    Test<short>();
*/
    Test<int>();
/*
    Test<long>();
    Test<long long>();
    Test<float>();
    Test<double>();

    Test<char2>();
    Test<short2>();
    Test<int2>();
    Test<long2>();
    Test<longlong2>();
    Test<float2>();
    Test<double2>();

    Test<TestFoo>();
    Test<TestBar>();
*/
    return 0;
}



