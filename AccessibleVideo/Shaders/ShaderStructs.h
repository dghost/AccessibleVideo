//
//  ShaderStructs.h
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/30/16.
//  Copyright © 2016 Luke Groeninger. All rights reserved.
//

#ifndef ShaderStructs_h
#define ShaderStructs_h

#include <simd/simd.h>

typedef struct
{
    matrix_float3x3 yuvToRGB;
} ColorParameters;


typedef struct
{
    vector_float4 primaryColor;
    vector_float4 secondaryColor;
    float lowThreshold;
    float highThreshold;
} FilterParameters;

typedef struct {
    vector_float2 xOffsets[3];
    vector_float2 yOffsets[3];
} BlurParameters;

#endif /* ShaderStructs_h */
