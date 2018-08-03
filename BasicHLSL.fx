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

float3 g_vViewPos; // 观察点
float3 g_vLightPos;

// 光照参数
float4 g_vLight;
float g_fLightScale; // 光源强度
float g_fDiffuseScale; // 漫反射所占比例
float g_fDiffSpecScale; // 漫反射、镜面反射比例总和
float g_fSpec; // 镜面反射系数
float g_fSpecEnhance; // 镜面反射增强
float g_fFactorMirror; // 镜面强度


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
		// 计算镜面反射系数
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

	// 添加
	float3 vToEye = normalize(g_vViewPos - In.PosW);
	float3 vLight = normalize(In.PosW - g_vLightPos);
	// 计算漫反射系数
	float factorDiffuse = saturate(dot(-vLight, In.NormalW));
	// 计算镜面反射系数
	float3 vReflect = normalize(reflect(vLight, In.NormalW));
	float3 vHalf = normalize(-vLight + vToEye);
	float factorSpecular = pow(saturate(dot(vReflect, vToEye)), g_fSpec);// Phone
	//factorSpecular = pow(saturate(dot(vHalf, In.NormalW)), g_fSpec);// Blinn-Phone
	// 镜面反射锐化
	factorSpecular = saturate(g_fSpecEnhance * factorSpecular);
	// 灯光颜色
	float4 light = g_vLight*g_fLightScale;
	// 镜面反射光源颜色覆盖
	float factorMirror = g_fFactorMirror;// 限制镜面反射光源颜色覆盖最大比例（描述物体表面镜面反射能力）
	float rateMirror = factorMirror * factorSpecular;// rateMirror 实现镜面反射光源覆盖
	// 漫反射、镜面反射比例
	float kd = g_fDiffuseScale;
	float ks = 1 - kd;
	// 比例纠正
	float ksum = kd + ks;
	kd *= g_fDiffSpecScale / ksum;
	ks *= g_fDiffSpecScale / ksum;
	kd = saturate(kd);
	ks = saturate(ks);


	// 光照计算
	// #0 原始（非单光源情况可行）
	Output.RGBColor =
		light * (color *factorDiffuse + factorSpecular);
	// #1 反射系数和限定（可行）
	Output.RGBColor =
		light *
		(color *factorDiffuse*kd + factorSpecular*ks);
	// #2 镜面反射光源颜色覆盖，高光区违反单调性
	//Output.RGBColor =
	//	color * light *
	//	(factorDiffuse + factorSpecular) * (1 - rateMirror)
	//	+ light * rateMirror;
	// #3 镜面反射光源颜色覆盖，（rate较大时高光区违反单调性，可以一定程度消除高光圈）
	rateMirror *= ks;
	Output.RGBColor =
		light *
		(color * factorDiffuse*kd + factorSpecular*ks) * (1 - rateMirror)
		+ light * factorSpecular * rateMirror;
	// #4 镜面反射光源颜色覆盖，较好的实现（可行，但是高光圈效果较明显）
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
