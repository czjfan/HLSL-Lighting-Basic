//--------------------------------------------------------------------------------------
// File: BasicHLSL.fx
//
// The effect file for the BasicHLSL sample.  
// 
// Copyright (c) Microsoft Corporation. All rights reserved.
//--------------------------------------------------------------------------------------


//--------------------------------------------------------------------------------------
// Global variables
//--------------------------------------------------------------------------------------
float4 g_MaterialAmbientColor;      // Material's ambient color
float4 g_MaterialDiffuseColor;      // Material's diffuse color
int g_nNumLights;

float3 g_LightDir[3];               // Light's direction in world space
float4 g_LightDiffuse[3];           // Light's diffuse color
float4 g_LightAmbient;              // Light's ambient color

texture g_MeshTexture;              // Color texture for mesh

float    g_fTime;                   // App's time in seconds
float4x4 g_mWorld;                  // World matrix for object
float4x4 g_mWorldViewProjection;    // World * View * Projection matrix

float3 g_vViewPos; // �۲��
float3 g_vLightPos;

// ���ղ���
float4 g_vLight;
float g_fLightScale; // ��Դǿ��
float g_fDiffuseScale; // ��������ռ����
float g_fDiffSpecScale; // �����䡢���淴������ܺ�
float g_fSpec; // ���淴��ϵ��
float g_fSpecEnhance; // ���淴����ǿ
float g_fFactorMirror; // ����ǿ��


//--------------------------------------------------------------------------------------
// Texture samplers
//--------------------------------------------------------------------------------------
sampler MeshTextureSampler =
sampler_state
{
	Texture = <g_MeshTexture>;
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};


//--------------------------------------------------------------------------------------
// Vertex shader output structure
//--------------------------------------------------------------------------------------
struct VS_OUTPUT
{
	float4 Position		: POSITION;   // vertex position
	float4 Color		: COLOR0;     // vertex diffuse color (note that COLOR0 is clamped from 0..1)
	float2 TextureUV	: TEXCOORD0;  // vertex texture coords

	float3 PosW			: TEXCOORD1;
	float3 NormalW      : TEXCOORD2;
};


//--------------------------------------------------------------------------------------
// This shader computes standard transform and lighting
//--------------------------------------------------------------------------------------
VS_OUTPUT RenderSceneVS(float4 vPos : POSITION,
	float3 vNormal : NORMAL,
	float2 vTexCoord0 : TEXCOORD0,
	float4 color : COLOR0,
	uniform int nNumLights,
	uniform bool bTexture,
	uniform bool bAnimate)
{
	VS_OUTPUT Output;
	float3 vNormalWorldSpace;

	//float4 vAnimatedPos = vPos;

	// Animation the vertex based on time and the vertex's object space position
	//if( bAnimate )
	//	vAnimatedPos += float4(vNormal, 0) * (sin(g_fTime+5.5)+0.5)*5;

	// Transform the position from object space to homogeneous projection space
	Output.Position = mul(vPos, g_mWorldViewProjection);

	// Transform the normal from object space to world space    
	vNormalWorldSpace = normalize(mul(vNormal, (float3x3)g_mWorld)); // normal (world space)

	bool bVertexLighting = false;
	if (bVertexLighting)
	{
		// Compute simple directional lighting equation
		float3 vTotalLightDiffuse = float3(0, 0, 0);
		for (int i = 0; i < nNumLights; i++)
			vTotalLightDiffuse += g_LightDiffuse[i] * max(0, dot(vNormalWorldSpace, g_LightDir[i]));

		float3 vPosW = normalize(mul(vPos, (float3x3)g_mWorld));
		float3 vToEye = normalize(g_vViewPos - vPosW);
		float3 vLight = normalize(vPosW - g_vLightPos);
		// ���㾵�淴��ϵ��
		float3 vReflect = normalize(reflect(vLight, vNormalWorldSpace));
		float factorSpecular = pow(saturate(dot(vReflect, vToEye)), 200);

		Output.Color.rgb = (0, 0, 0, 1);
		float4 colorAmbient = g_MaterialAmbientColor*color;
		float4 colorDiffuse = g_MaterialDiffuseColor*color;
		float4 colorSpecular = color;
		float4 lightAmbient = g_LightAmbient;
		float3 lightDiffuse = vTotalLightDiffuse;// TODO float4?
		float4 lightSpecular = g_LightDiffuse[0];
		Output.Color.rgb =
			(colorAmbient * lightAmbient +
				colorDiffuse * lightDiffuse +
				colorSpecular * lightSpecular * factorSpecular);
		Output.Color.a = 1.0f;
	}
	else
		Output.Color = color;
	// other param
	float4 worldPosition = mul(float4(vPos.xyz, 1.0), g_mWorld);
	Output.PosW = worldPosition / worldPosition.w;
	Output.NormalW = vNormalWorldSpace;

	// Just copy the texture coordinate through
	if (bTexture)
		Output.TextureUV = vTexCoord0;
	else
		Output.TextureUV = 0;

	return Output;
}


//--------------------------------------------------------------------------------------
// Pixel shader output structure
//--------------------------------------------------------------------------------------
struct PS_OUTPUT
{
	float4 RGBColor : COLOR0;  // Pixel color    
};


//--------------------------------------------------------------------------------------
// This shader outputs the pixel's color by modulating the texture's
//       color with diffuse material color
//--------------------------------------------------------------------------------------
PS_OUTPUT RenderScenePS(VS_OUTPUT In,
	float4 color : COLOR0,
	uniform bool bTexture)
{
	PS_OUTPUT Output;

	// ���
	float3 vToEye = normalize(g_vViewPos - In.PosW);
	float3 vLight = normalize(In.PosW - g_vLightPos);
	// ����������ϵ��
	float factorDiffuse = saturate(dot(-vLight, In.NormalW));
	// ���㾵�淴��ϵ��
	float3 vReflect = normalize(reflect(vLight, In.NormalW));
	float3 vHalf = normalize(-vLight + vToEye);
	float factorSpecular = pow(saturate(dot(vReflect, vToEye)), g_fSpec);// Phone
	//factorSpecular = pow(saturate(dot(vHalf, In.NormalW)), g_fSpec);// Blinn-Phone
	// ���淴����
	factorSpecular = saturate(g_fSpecEnhance * factorSpecular);
	// �ƹ���ɫ
	float4 light = g_vLight*g_fLightScale;
	// ���淴���Դ��ɫ����
	float factorMirror = g_fFactorMirror;// ���ƾ��淴���Դ��ɫ����������������������澵�淴��������
	float rateMirror = factorMirror * factorSpecular;// rateMirror ʵ�־��淴���Դ����
	// �����䡢���淴�����
	float kd = g_fDiffuseScale;
	float ks = 1 - kd;
	// ��������
	float ksum = kd + ks;
	kd *= g_fDiffSpecScale / ksum;
	ks *= g_fDiffSpecScale / ksum;
	kd = saturate(kd);
	ks = saturate(ks);


	// ���ռ���
	// #0 ԭʼ���ǵ���Դ������У�
	Output.RGBColor =
		light * (color *factorDiffuse + factorSpecular);
	// #1 ����ϵ�����޶������У�
	Output.RGBColor =
		light *
		(color *factorDiffuse*kd + factorSpecular*ks);
	// #2 ���淴���Դ��ɫ���ǣ��߹���Υ��������
	//Output.RGBColor =
	//	color * light *
	//	(factorDiffuse + factorSpecular) * (1 - rateMirror)
	//	+ light * rateMirror;
	// #3 ���淴���Դ��ɫ���ǣ���rate�ϴ�ʱ�߹���Υ�������ԣ�����һ���̶������߹�Ȧ��
	rateMirror *= ks;
	Output.RGBColor =
		light *
		(color * factorDiffuse*kd + factorSpecular*ks) * (1 - rateMirror)
		+ light * factorSpecular * rateMirror;
	// #4 ���淴���Դ��ɫ���ǣ��Ϻõ�ʵ�֣����У����Ǹ߹�ȦЧ�������ԣ�
	/*Output.RGBColor =
	color * kd * light * factorDiffuse
	+ (color * ks * light * factorSpecular * (1 - rateMirror)
	+ light * factorSpecular * rateMirror);*/

	// Lookup mesh texture and modulate it with diffuse
	/*if (bTexture)
	Output.RGBColor = tex2D(MeshTextureSampler, In.TextureUV) * Output.RGBColor;
	else
	Output.RGBColor = In.Color;*/

	return Output;
}


//--------------------------------------------------------------------------------------
// Renders scene to render target
//--------------------------------------------------------------------------------------
technique RenderSceneWithTexture1Light
{
	pass P0
	{
		VertexShader = compile vs_2_0 RenderSceneVS(1, true, true);
		PixelShader = compile ps_2_0 RenderScenePS(true); // trivial pixel shader (could use FF instead if desired)
	}
}

technique RenderSceneWithTexture2Light
{
	pass P0
	{
		VertexShader = compile vs_2_0 RenderSceneVS(2, true, true);
		PixelShader = compile ps_2_0 RenderScenePS(true); // trivial pixel shader (could use FF instead if desired)
	}
}

technique RenderSceneWithTexture3Light
{
	pass P0
	{
		VertexShader = compile vs_2_0 RenderSceneVS(3, true, true);
		PixelShader = compile ps_2_0 RenderScenePS(true); // trivial pixel shader (could use FF instead if desired)
	}
}

technique RenderSceneNoTexture
{
	pass P0
	{
		VertexShader = compile vs_2_0 RenderSceneVS(1, false, false);
		PixelShader = compile ps_2_0 RenderScenePS(false); // trivial pixel shader (could use FF instead if desired)
	}
}
