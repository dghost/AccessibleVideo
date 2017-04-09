//
//  Canny.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/11/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

#include "Common.metal"

constant half invPi = 1.0/3.1415926535;


half unpack(half angle);

// sample the angle
half unpack(half angle)
{
    // convert it from 0.0 - 1.0 to -pi/2 to pi/2
    half theta = (angle - 0.5) * 180.0;
    if (theta < 0.0)
        theta += 180.0;
    return theta;
}


fragment half4 CannySobelPass(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    
    half m11 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).a;
    half m12 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2( 0,+1)).a;
    half m13 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).a;
    half m21 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1, 0)).a;
    half m22 = currentFrame.sample(bilinear, inFrag.m_TexCoord).a;
    half m23 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1, 0)).a;
    half m31 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).a;
    half m32 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2( 0,-1)).a;
    half m33 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).a;

    half2 hv;
    half m31m13 = m31 - m13;
    half m11m33 = m33 - m11;
    half m32m12 = m32 - m12;
    half m21m23 = m21 - m23;
    hv.x = m32m12 + m32m12 + m11m33 + m31m13;
    hv.y = m21m23 + m21m23 - m11m33 + m31m13;
    
    half sobel = length(hv);

    half theta = atan2(hv.x,hv.y) * invPi + 0.5;
    
    half4 color = half4(m22,sobel,theta,1.0);
    return color;
}




fragment half4 CannyMagnitude(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half2 temp = lastStage.sample(bilinear, inFrag.m_TexCoord).gb;
    half angle = unpack(temp.g);
    half m11 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).g;
    half m12 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,+1)).g;
    half m13 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).g;
    half m21 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1, 0)).g;
    half m22 = temp.r;
    half m23 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1, 0)).g;
    half m31 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).g;
    half m32 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,-1)).g;
    half m33 = lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).g;
    
    bool test = ((angle <= 22.5 || angle >= 157.5)&&(m22 > m21 && m22 > m23))
                || ((angle <= 112.5 && angle >= 77.5)&&(m22 > m12 && m22 > m32))
                || ((angle <= 77.5 && angle >= 22.5)&&(m22 > m11 && m22 > m33))
                || ((angle >= 112.5 && angle <= 157.5)&&(m22 > m13 && m22 > m31));
                
    half4 color;
    
    if (test)
        color = half4(m22,m22,m22,1.0);
    else
        color = half4(half3(0.0),1.0);
    
    return color;
}

fragment half4 CannyThreshold(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half m22 = lastStage.sample(bilinear, inFrag.m_TexCoord).r;
    half4 color = half4(half3(0.0),1.0);

    half highThreshold = HIGH_THRESHOLD;
    
    if (m22 >= highThreshold )
    {
        color.rgb = PRIMARY_COLOR.rgb;
    }
    else if (m22 >= LOW_THRESHOLD){
#define m11 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).r
#define m12 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,+1)).r
#define m13 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).r
#define m21 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1, 0)).r
#define m23 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1, 0)).r
#define m31 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).r
#define m32 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,-1)).r
#define m33 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).r
        if ((m11 >= highThreshold) || (m12 >= highThreshold) || (m13 >= highThreshold ) ||
            (m21 >= highThreshold) || (m23 >= highThreshold) ||
            (m31 >= highThreshold) || (m32 >= highThreshold) || (m33 >= highThreshold))
        {
            color.rgb = PRIMARY_COLOR.rgb;
        } else {
            color.rgb = SECONDARY_COLOR.rgb;
        }
    }
    return color;
}

fragment half4 CannyThresholdComposite(FILTER_SHADER_ARGS)
{
    half highThreshold = HIGH_THRESHOLD;
    
    half m22 = lastStage.sample(bilinear, inFrag.m_TexCoord).r;
    
    half3 color = originalFrame.sample(bilinear, inFrag.m_TexCoord).rgb;

    if (m22 >= highThreshold )
    {
        half4 blendColor = PRIMARY_COLOR;
        color *= (1.0 - blendColor.a);
        color += (blendColor.rgb * blendColor.a);
    } else if (m22 >= LOW_THRESHOLD){
#define m11 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).r
#define m12 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,+1)).r
#define m13 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).r
#define m21 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1, 0)).r
#define m23 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1, 0)).r
#define m31 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).r
#define m32 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,-1)).r
#define m33 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).r
        
        if ((m11 >= highThreshold) || (m12 >= highThreshold) || (m13 >= highThreshold ) ||
            (m21 >= highThreshold) || (m23 >= highThreshold) ||
            (m31 >= highThreshold) || (m32 >= highThreshold) || (m33 >= highThreshold))
        {
            half4 blendColor = PRIMARY_COLOR;
            color *= (1.0 - blendColor.a);
            color += (blendColor.rgb * blendColor.a);
        } else {
            half4 blendColor = SECONDARY_COLOR;
            color *= (1.0 - blendColor.a);
            color += (blendColor.rgb * blendColor.a);
        }
    }

    return half4(color,1.0);
}

fragment half4 CannyComic(FILTER_SHADER_ARGS)
{
    // parameters that define the comic effect
#define LINE_SLOPE -0.8h
#define LINE_INTERVAL 30.0h
#define LINE_STRENGTH 2.0h
#define BLACK_THRESHOLD 0.2h
#define WHITE_THRESHOLD 0.6h
    half highThreshold = HIGH_THRESHOLD * 2.0   ;
    
    bool result = false;
    half m22 = lastStage.sample(bilinear, inFrag.m_TexCoord).r;
    half3 color;

    if (m22 >= highThreshold)
    {
        result = true;
    } else if (m22 >= LOW_THRESHOLD){
#define m11 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).r
#define m12 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,+1)).r
#define m13 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).r
#define m21 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1, 0)).r
#define m23 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1, 0)).r
#define m31 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).r
#define m32 lastStage.sample(bilinear, inFrag.m_TexCoord,int2( 0,-1)).r
#define m33 lastStage.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).r
        
        if ((m11 >= highThreshold) || (m12 >= highThreshold) || (m13 >= highThreshold ) ||
            (m21 >= highThreshold) || (m23 >= highThreshold) ||
            (m31 >= highThreshold) || (m32 >= highThreshold) || (m33 >= highThreshold))
        {
            result = true;
        }
    }
    
    // set pixel to white if it passed, or black otherwise

    if (result) {
        color = SECONDARY_COLOR.rgb;
    } else {
        half gray = originalFrame.sample(bilinear, inFrag.m_TexCoord).a;
        if (gray > WHITE_THRESHOLD)
        {
            color = PRIMARY_COLOR.rgb;
        } else if (gray < BLACK_THRESHOLD)
        {
            color = SECONDARY_COLOR.rgb;
        } else
        {
            half2 pixel = half2(inFrag.m_TexCoord) * half2(lastStage.get_width(),lastStage.get_height());
            half b = LINE_SLOPE * pixel.x - pixel.y;
            color = (floor(fmod(b,LINE_INTERVAL)) - LINE_STRENGTH  > 0.0) ? PRIMARY_COLOR.rgb : SECONDARY_COLOR.rgb;
        }
    }
    return half4(color,1.0);
}

