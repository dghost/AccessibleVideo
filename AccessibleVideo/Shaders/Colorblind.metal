//
//  Colorblind.metal
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/11/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

#include "Common.metal"

fragment half4 tritanope(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half3x3 errorshift = {{0.0, 0.7, 0.7},
                          {0.0, 1.0, 0.0},
                          {0.0, 0.0, 1.0}};
    
    half3x3 tritanope = {{ 0.49325795,  0.49325586, -3.01086514},
                         { 0.50674879,  0.50673758,  3.01090517},
                         { 0.00000075, -0.00000073,  1.00000447}};
    
    half3 rgb = originalFrame.sample(bilinear, inFrag.m_TexCoord).rgb;
    half3 shift = errorshift * (rgb - (tritanope * rgb));
    return half4(shift + rgb,1.0);
}

fragment half4 deuteranope(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half3x3 errorshift = {{0.0, 0.7, 0.7},
                          {0.0, 1.0, 0.0},
                          {0.0, 0.0, 1.0}};
    
    half3x3 deuteranope = {{ 0.29275078,  0.2927497 , -0.02233648},
                           { 0.70725186,  0.70724921,  0.02233656},
                           { 0.00000052, -0.00000021,  1.00000002}};
    
    half3 rgb = originalFrame.sample(bilinear, inFrag.m_TexCoord).rgb;
    half3 shift = errorshift * (rgb - (deuteranope * rgb));
    return half4(shift + rgb,1.0);
}

fragment half4 protanope(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half3x3 errorshift = {{0.0, 0.7, 0.7},
                          {0.0, 1.0, 0.0},
                          {0.0, 0.0, 1.0}};
                        
    half3x3 protanope = {{ 0.11238227,  0.112383  ,  0.00400576},
                         { 0.88761197,  0.88761773, -0.00400573},
                         {-0.0000012 ,  0.00000015,  1.00000001}};
    
    half3 rgb = originalFrame.sample(bilinear, inFrag.m_TexCoord).rgb;
    half3 shift = errorshift * (rgb - (protanope * rgb));
    return half4(shift + rgb,1.0);
}
