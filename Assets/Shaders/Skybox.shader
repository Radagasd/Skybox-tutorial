Shader "KelvinvanHoorn/Skybox"
{
    Properties
    {
        [NoScaleOffset] _SunZenithGrad ("Sun-Zenith gradient", 2D) = "white" {}
        [NoScaleOffset] _ViewZenithGrad ("View-Zenith gradient", 2D) = "white" {}
        [NoScaleOffset] _SunViewGrad ("Sun-View gradient", 2D) = "white" {}
        _SunRadius ("Sun radius", Range(0,1)) = 0.05
        _MoonRadius ("Moon radius", Range(0,1)) = 0.05
        _MoonExposure ("Moon exposure", Range(-16, 16)) = 0
        [NoScaleOffset] _MoonCubeMap ("Moon cube map", Cube) = "black" {}
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 posOS    : POSITION;
            };

            struct v2f
            {
                float4 posCS        : SV_POSITION;
                float3 viewDirWS    : TEXCOORD0;
            };

            v2f Vertex(Attributes IN)
            {
                v2f OUT = (v2f)0;
    
                VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.posOS.xyz);
    
                OUT.posCS = vertexInput.positionCS;
                OUT.viewDirWS = vertexInput.positionWS;

                return OUT;
            }

            TEXTURE2D(_SunZenithGrad);      SAMPLER(sampler_SunZenithGrad);
            TEXTURE2D(_ViewZenithGrad);     SAMPLER(sampler_ViewZenithGrad);
            TEXTURE2D(_SunViewGrad);        SAMPLER(sampler_SunViewGrad);
            TEXTURECUBE(_MoonCubeMap);      SAMPLER(sampler_MoonCubeMap);

            float3 _SunDir, _MoonDir;
            float _SunRadius, _MoonRadius;
            float _MoonExposure;
            float4x4 _MoonSpaceMatrix;

            float GetSunMask(float sunViewDot, float sunRadius)
            {
                float stepRadius = 1 - sunRadius * sunRadius;
                return step(stepRadius, sunViewDot);
            }

            // From Inigo Quilez, https://www.iquilezles.org/www/articles/intersectors/intersectors.htm
            float sphIntersect(float3 rayDir, float3 spherePos, float radius)
            {
                float3 oc = -spherePos;
                float b = dot(oc, rayDir);
                float c = dot(oc, oc) - radius * radius;
                float h = b * b - c;
                if(h < 0.0) return -1.0;
                h = sqrt(h);
                return -b - h;
            }

            float3 GetMoonTexture(float3 normal)
            {
                float3 uvw = mul(_MoonSpaceMatrix, float4(normal, 0)).xyz;

                float3x3 correctionMatrix = float3x3(0, -0.2588190451, -0.9659258263,
                    0.08715574275, 0.9622501869, -0.2578341605,
                    0.9961946981, -0.08418598283, 0.02255756611);
                uvw = mul(correctionMatrix, uvw);
                
                return SAMPLE_TEXTURECUBE(_MoonCubeMap, sampler_MoonCubeMap, uvw).rgb;
            }

            float4 Fragment (v2f IN) : SV_TARGET
            {
                float3 viewDir = normalize(IN.viewDirWS);

                // Main angles
                float sunViewDot = dot(_SunDir, viewDir);
                float sunZenithDot = _SunDir.y;
                float viewZenithDot = viewDir.y;
                float sunMoonDot = dot(_SunDir, _MoonDir);

                float sunViewDot01 = (sunViewDot + 1.0) * 0.5;
                float sunZenithDot01 = (sunZenithDot + 1.0) * 0.5;

                // Sky colours
                float3 sunZenithColor = SAMPLE_TEXTURE2D(_SunZenithGrad, sampler_SunZenithGrad, float2(sunZenithDot01, 0.5)).rgb;

                float3 viewZenithColor = SAMPLE_TEXTURE2D(_ViewZenithGrad, sampler_ViewZenithGrad, float2(sunZenithDot01, 0.5)).rgb;
                float vzMask = pow(saturate(1.0 - viewZenithDot), 4);

                float3 sunViewColor = SAMPLE_TEXTURE2D(_SunViewGrad, sampler_SunViewGrad, float2(sunZenithDot01, 0.5)).rgb;
                float svMask = pow(saturate(sunViewDot), 4);

                float3 skyColor = sunZenithColor + vzMask * viewZenithColor + svMask * sunViewColor;

                // The sun
                float sunMask = GetSunMask(sunViewDot, _SunRadius);
                float3 sunColor = _MainLightColor.rgb * sunMask;

                // The moon
                float moonIntersect = sphIntersect(viewDir, _MoonDir, _MoonRadius);
                float moonMask = moonIntersect > -1 ? 1 : 0;
                float3 moonNormal = normalize(_MoonDir - viewDir * moonIntersect);
                float moonNdotL = saturate(dot(moonNormal, -_SunDir));
                float3 moonTexture = GetMoonTexture(moonNormal);
                float3 moonColor = moonMask * moonNdotL * exp2(_MoonExposure) * moonTexture;

                float3 col = skyColor + sunColor + moonColor;
                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}