//
//  ShaderStructs.h
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/30/16.
//  Copyright © 2016 Luke Groeninger. All rights reserved.
//

#ifndef ShaderStructs_h
#define ShaderStructs_h

typedef struct
{
    float yuvToRGB[3][4];
} ColorParameters;


typedef struct
{
    unsigned char r, g, b, a;
} Color;

typedef struct
{
    float lowThreshold;
    float highThreshold;
    Color primaryColor;
    Color secondaryColor;
} FilterParameters;

typedef struct {
    float x, y;
} Offset;

typedef struct {
    Offset xOffsets[3];
    Offset yOffsets[3];
} BlurParameters;

#endif /* ShaderStructs_h */
