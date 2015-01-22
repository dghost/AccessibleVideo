//
//  Shaders.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 9/15/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//


// Base shaders
//
// These are required for program to run
//

#include "Common.metal"

vertex VertexOut defaultVertex( VertexIn vert [[ stage_in ]], unsigned int vid [[ vertex_id ]])
{
    VertexOut outVertices;
    outVertices.m_Position = float4(vert.m_Position,0.0,1.0);
    outVertices.m_TexCoord = vert.m_TexCoord;
    return outVertices;
}

fragment half4 yuv_rgb(YUV_SHADER_ARGS)
{
    float3 yuv;
    yuv.x = lumaTex.sample(bilinear, inFrag.m_TexCoord).r;
    yuv.yz = chromaTex.sample(bilinear,inFrag.m_TexCoord).rg - float2(0.5);
    return half4(half3(colorParameters->yuvToRGB * yuv),yuv.x);
}

fragment half4 yuv_grayscale(YUV_SHADER_ARGS)
{
    return half4(lumaTex.sample(bilinear, inFrag.m_TexCoord).r);
}

fragment half4 blit(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half4 color = half4(lastStage.sample(bilinear, inFrag.m_TexCoord).rgb,1.0);
    return color;
}


fragment half4 invert(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half3 inverse = half3(1.0) - lastStage.sample(bilinear, inFrag.m_TexCoord).rgb;
    return half4(inverse,1.0);
}

