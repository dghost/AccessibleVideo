//
//  Common.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/11/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//



// Common shader definitions
//
// These are required for program to run, and ensure consistent behavior across shaders
//


#include <metal_stdlib>
#include <metal_pack>

#include "ShaderStructs.h"
using namespace metal;

struct VertexIn
{
    float2 m_Position [[ attribute(0) ]];
    float2 m_TexCoord [[ attribute(1) ]];
};

struct VertexOut
{
    float4 m_Position [[ position ]];
    float2 m_TexCoord [[ user(texturecoord) ]];
};

#define PRIMARY_COLOR half4(filterParameters->primaryColor)
#define SECONDARY_COLOR half4(filterParameters->secondaryColor)
#define HIGH_THRESHOLD half(filterParameters->highThreshold)
#define LOW_THRESHOLD half(filterParameters->lowThreshold)

#define YUV_SHADER_ARGS  VertexOut      inFrag    [[ stage_in ]],\
                         texture2d<float>  lumaTex     [[ texture(0) ]],\
                         texture2d<float>  chromaTex     [[ texture(1) ]],\
                         sampler bilinear [[ sampler(1) ]], \
                         constant ColorParameters *colorParameters [[ buffer(0) ]]

#define FILTER_SHADER_ARGS  VertexOut        inFrag     [[ stage_in ]],\
                            texture2d<half>  lastStage  [[ texture(0) ]],\
                            texture2d<half>  currentFrame     [[ texture(1) ]],\
                            texture2d<half>  originalFrame     [[ texture(2) ]],\
                            sampler bilinear [[ sampler(1) ]], \
                            constant FilterParameters *filterParameters [[ buffer(0) ]]

#define FILTER_SHADER_ARGS_LAST_ONLY    VertexOut        inFrag     [[ stage_in ]],\
                                        texture2d<half>  lastStage  [[ texture(0) ]],\
                                        sampler bilinear [[ sampler(1) ]], \
                                        constant FilterParameters *filterParameters [[ buffer(0) ]]


#define FILTER_SHADER_ARGS_FRAME_ONLY   VertexOut        inFrag     [[ stage_in ]],\
                                        texture2d<half>  currentFrame     [[ texture(1) ]],\
                                        texture2d<half>  originalFrame     [[ texture(2) ]],\
                                        sampler bilinear [[ sampler(1) ]], \
                                        constant FilterParameters *filterParameters [[ buffer(0) ]]
