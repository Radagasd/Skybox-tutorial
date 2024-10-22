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

        [NoScaleOffset] _StarCubeMap ("Star cube map", Cube) = "black" {}
        _StarExposure ("Star exposure", Range(-16, 16)) = 0
        _StarPower ("Star power", Range(1,5)) = 1
        _StarLatitude ("Star latitude", Range(-90, 90)) = 0
        _StarSpeed ("Star speed", Float) = 0.001

        [NoScaleOffset] _ConstellationCubeMap ("Constellation cube map", Cube) = "blank" {}
        _ConstellationColor ("Constellation color", Color) = (0,0.3,0.6,1)
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
            TEXTURECUBE(_StarCubeMap);      SAMPLER(sampler_StarCubeMap);
            TEXTURECUBE(_ConstellationCubeMap); SAMPLER(sampler_ConstellationCubeMap);

            float3 _SunDir, _MoonDir;
            float _SunRadius, _MoonRadius;
            float _MoonExposure, _StarExposure;
            float _StarPower;
            float _StarLatitude, _StarSpeed;
            float3 _ConstellationColor;
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

            // Construct a rotation matrix that rotates around a particular axis by angle
            // From: https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
            float3x3 AngleAxis3x3(float angle, float3 axis)
            {
                float c, s;
                sincos(angle, s, c);

                float t = 1 - c;
                float x = axis.x;
                float y = axis.y;
                float z = axis.z;

                return float3x3(
                    t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                    t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                    t * x * z - s * y, t * y * z + s * x, t * z * z + c
                    );
            }

            float3 GetMoonTexture(float3 normal)
            {
                float3 uvw = mul(_MoonSpaceMatrix, float4(normal, 0)).xyz;

                // Found through trial and error resulting in mul(AngleAxis3x3(0.5*PI, float3(0,1,0)), AngleAxis3x3(-0.08*PI, float3(1,0,0)));
                float3x3 correctionMatrix = float3x3( 0, -0.24869, 0.968583, 0, 0.968583, 0.24869, -1, 0, 0);

                uvw = mul(correctionMatrix, uvw);

                return SAMPLE_TEXTURECUBE(_MoonCubeMap, sampler_MoonCubeMap, uvw).rgb;
            }

            // Rotate the view direction, tilt with latitude, spin with time
            float3 GetStarUVW(float3 viewDir, float latitude, float localSiderealTime)
            {
                // tilt = 0 at the north pole, where latitude = 90 degrees
                float tilt = PI * (latitude - 90) / 180;
                float3x3 tiltRotation = AngleAxis3x3(tilt, float3(1,0,0));

                // 0.75 is a texture offset for lST = 0 equals noon
                float spin = (0.75-localSiderealTime) * 2 * PI;
                float3x3 spinRotation = AngleAxis3x3(spin, float3(0, 1, 0));
                
                // The order of rotation is important
                float3x3 fullRotation = mul(spinRotation, tiltRotation);

                return mul(fullRotation,  viewDir);
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
                float3 moonNormal = normalize(viewDir * moonIntersect - _MoonDir);
                float moonNdotL = saturate(dot(moonNormal, _SunDir));
                float3 moonTexture = GetMoonTexture(moonNormal);
                float3 moonColor = moonMask * moonNdotL * exp2(_MoonExposure) * moonTexture;

                // The stars
                float3 starUVW = GetStarUVW(viewDir, _StarLatitude, _Time.y * _StarSpeed % 1);
                float3 starColor = SAMPLE_TEXTURECUBE_BIAS(_StarCubeMap, sampler_StarCubeMap, starUVW, -1).rgb;
                starColor = pow(abs(starColor), _StarPower);
                float starStrength = (1 - sunViewDot01) * (saturate(-sunZenithDot));
                starColor *= (1 - sunMask) * (1 - moonMask) * exp2(_StarExposure) * starStrength;

                // The constellations
                float3 constColor = SAMPLE_TEXTURECUBE(_ConstellationCubeMap, sampler_ConstellationCubeMap, starUVW).rgb * _ConstellationColor;
                constColor *= (1 - sunMask) * (1 - moonMask) * starStrength;

                // Solar eclipse
                float solarEclipse01 = smoothstep(1 - _SunRadius * _SunRadius, 1.0, sunMoonDot);
                skyColor *= lerp(1, 0.4, solarEclipse01);
                sunColor *= (1 - moonMask) * lerp(1, 16, solarEclipse01);

                // Lunar eclipse
                float lunarEclipseMask = 1 - step(1 - _SunRadius * _SunRadius, -sunViewDot);
                float lunarEclipse01 = smoothstep(1 - _SunRadius * _SunRadius * 0.05, 1.0, -sunMoonDot);
                moonColor *= lerp(lunarEclipseMask, float3(0.3,0.05,0), lunarEclipse01);

                float3 col = skyColor + sunColor + moonColor + starColor + constColor;
                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }
}