//
//  Canny.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 10/7/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

#include "Common.metal"

fragment half4 sobel_color(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half3 m11 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).rgb;
    half3 m12 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,+1)).rgb;
    half3 m13 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).rgb;
    half3 m21 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,0)).rgb;
    //    half3 m22 = currentFrame.sample(bilinear, inFrag.m_TexCoord).rgb;
    half3 m23 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,0)).rgb;
    half3 m31 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).rgb;
    half3 m32 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,-1)).rgb;
    half3 m33 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).rgb;
    
    half3 m31m13 = m31 - m13;
    half3 m11m33 = m33 - m11;
    half3 m32m12 = m32 - m12;
    half3 m21m23 = m21 - m23;
    half3 H = m32m12 + m32m12 + m11m33 + m31m13;
    half3 V = m21m23 + m21m23 - m11m33 + m31m13;
    
    half3 sobel = sqrt(H*H+V*V);
    
    half4 color = half4(sobel,1.0);
    return color;
}


fragment half4 sobel_composite(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half4 blendColor = PRIMARY_COLOR;
    half m11 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).a;
    half m12 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,+1)).a;
    half m13 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).a;
    half m21 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,0)).a;
    half m23 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,0)).a;
    half m31 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).a;
    half m32 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,-1)).a;
    half m33 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).a;
    
    half2 hv;
    half m31m13 = m31 - m13;
    half m11m33 = m33 - m11;
    half m32m12 = m32 - m12;
    half m21m23 = m21 - m23;
    hv.x = m32m12 + m32m12 + m11m33 + m31m13;
    hv.y = m21m23 + m21m23 - m11m33 + m31m13;
    
    blendColor.a *= length(hv);

    half3 color = originalFrame.sample(bilinear, inFrag.m_TexCoord).rgb * (1.0 - blendColor.a);
    color += blendColor.rgb * blendColor.a;
    return half4(color,1.0);
}