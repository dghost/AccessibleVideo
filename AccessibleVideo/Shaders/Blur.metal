//
//  Blur.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/9/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//


// Blur shaders
//
// These are required for program to run, and apply a seperable gaussian blur to the image
//


#include "Common.metal"



fragment half4 BlurX(VertexOut        inFrag        [[ stage_in ]],
                     texture2d<half>  sourceTexture [[ texture(0) ]],
                     sampler nearest [[ sampler(0) ]])
{
    half4 m21 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(-1,0));
    half4 m22 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(0,0));
    half4 m23 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(+1,0));
    
    half4 color = 0.25 * (m21 + m23) + 0.5 * m22;
    return color;
}

fragment half4 BlurY(VertexOut        inFrag        [[ stage_in ]],
                     texture2d<half>  sourceTexture [[ texture(0) ]],
                     sampler nearest [[ sampler(0) ]])
{
    half4 m12 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(0,+1));
    half4 m22 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(0,0));
    half4 m32 = sourceTexture.sample(nearest, inFrag.m_TexCoord,int2(0,-1));
    
    half4 color = 0.25 * (m12 + m32) + 0.5 * m22;
    return color;
}

//
// High quality linear sampled gaussian blur
// Source: http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/
//

constant half weights[] = { 0.2270270270, 0.3162162162, 0.0702702703 };

fragment half4 BlurX_HQ(VertexOut        inFrag        [[ stage_in ]],
                        texture2d<half>  sourceTexture [[ texture(0) ]],
                        sampler bilinear [[ sampler(1) ]],
                        constant BlurParameters *blurParameters [[ buffer(0) ]])
{
    half4 color = half4(0.0);
    
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord - blurParameters->xOffsets[2]) * weights[2];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord - blurParameters->xOffsets[1]) * weights[1];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord) * weights[0];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord + blurParameters->xOffsets[1]) * weights[1];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord + blurParameters->xOffsets[2]) * weights[2];
    return color;
}

fragment half4 BlurY_HQ(VertexOut        inFrag        [[ stage_in ]],
                        texture2d<half>  sourceTexture [[ texture(0) ]],
                        sampler bilinear [[ sampler(1) ]],
                        constant BlurParameters *blurParameters [[ buffer(0) ]])
{
    half4 color = half4(0.0);
    
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord - blurParameters->yOffsets[2]) * weights[2];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord - blurParameters->yOffsets[1]) * weights[1];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord) * weights[0];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord + blurParameters->yOffsets[1]) * weights[1];
    color += sourceTexture.sample(bilinear, inFrag.m_TexCoord + blurParameters->yOffsets[2]) * weights[2];
    return color;
}
