/* helper functions */

// light fallback
vector<half, 4> getlightDir() {
    Light mainLight = GetMainLight();
    
    // Check if light direction is zero using individual components
    bool isZero = all(mainLight.direction.xyz == float3(0,0,0));
    
    // Return appropriate direction as half4
    vector<half, 4> lightDir = isZero ? 
                              vector<half, 4>(1, 1, 0, 0) :
                              vector<half, 4>(mainLight.direction.xyz, 0);
    return lightDir;
}

// map range function
float mapRange(const float min_in, const float max_in, const float min_out, const float max_out, const float value){
    float slope = (max_out - min_out) / (max_in - min_in);
    
    return min_out + slope * (value - min_in);
}

float lerpByZ(const float startScale, const float endScale, const float startZ, const float endZ, const float z){
   float t = (z - startZ) / max(endZ - startZ, 0.001);
   t = saturate(t);
   return lerp(startScale, endScale, t);
}

// environment lighting function
vector<half, 4> calculateEnvLighting(vector<float, 3> vertexWSInput) {
    // Initialize point lights
    vector<half, 3> firstPointLight = 0;
    vector<half, 3> secondPointLight = 0;
    vector<half, 3> thirdPointLight = 0;
    vector<half, 3> fourthPointLight = 0;
    uint lightIndex = 0;

    #if defined(_ADDITIONAL_LIGHTS)
        #if USE_FORWARD_PLUS
        // Forward+ specific directional lights
        UNITY_LOOP 
        for (uint dirLightIndex = 0; dirLightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); dirLightIndex++)
        {
            // Remove screen space UV calculation, pass half4(1,1,1,1) for no attenuation
            Light light = GetAdditionalLight(dirLightIndex, vertexWSInput, half4(1,1,1,1));
            float lightAtten = light.distanceAttenuation * light.shadowAttenuation;
            vector<half, 3> lightColor = light.color * lightAtten;
            
            if (lightIndex < 4) {
                switch(lightIndex++) {
                    case 0: firstPointLight = lightColor; break;
                    case 1: secondPointLight = lightColor; break;
                    case 2: thirdPointLight = lightColor; break;
                    case 3: fourthPointLight = lightColor; break;
                }
            }
        }
        #endif

        // Regular additional lights
        float pixelLightCount = GetAdditionalLightsCount();
        LIGHT_LOOP_BEGIN(pixelLightCount)
            Light light;
            #if USE_FORWARD_PLUS
                light = GetAdditionalLight(lightIndex, vertexWSInput, half4(1,1,1,1));
            #else
                light = GetAdditionalLight(lightIndex, vertexWSInput);
            #endif

            float lightAtten = light.distanceAttenuation * light.shadowAttenuation;
            vector<half, 3> lightColor = light.color * lightAtten;
                
            if (lightIndex < 4) {
                switch(lightIndex) {
                    case 0: firstPointLight = lightColor; break;
                    case 1: secondPointLight = lightColor; break;
                    case 2: thirdPointLight = lightColor; break;
                    case 3: fourthPointLight = lightColor; break;
                }
            }
        LIGHT_LOOP_END
    #endif

    // Combine lights
    vector<half, 3> pointLightCalc = firstPointLight;
    pointLightCalc = max(pointLightCalc, secondPointLight);
    pointLightCalc = max(pointLightCalc, thirdPointLight);
    pointLightCalc = max(pointLightCalc, fourthPointLight);

    // Get main light
    Light mainLight = GetMainLight();
    vector<half, 4> environmentLighting = vector<half, 4>(mainLight.color * mainLight.distanceAttenuation, 1);
    
    // Combine with point lights
    environmentLighting = max(environmentLighting, vector<half, 4>(pointLightCalc, 1));
    
    return environmentLighting;
}

// rim light function
vector<half, 4> calculateRimLight(const vector<float, 3> normalInput, const vector<float, 4> screenPosInput, 
                                  const float RimLightIntensityInput, const float RimLightThicknessInput, 
                                  const float factor){
    // basically view-space normals, except we cannot use the normal map so get mesh's raw normals
    vector<half, 3> rimNormals = TransformObjectToWorldNormal(normalInput);
    rimNormals = mul(UNITY_MATRIX_V, rimNormals);

    // https://github.com/TwoTailsGames/Unity-Built-in-Shaders/blob/master/CGIncludes/UnityDeferredLibrary.cginc#L152
    vector<half, 2> screenPos = screenPosInput.xy / screenPosInput.w;

    // sample depth texture and get it in linear form untouched
    half linearDepth = SampleSceneDepth(screenPos.xy);
     linearDepth = LinearEyeDepth(linearDepth, _ZBufferParams);

    // now we modify screenPos to offset another sampled depth texture
    screenPos = screenPos + (rimNormals.x * (0.00125 * max(_ScreenParams.x * 
                0.00025, 1) + ((RimLightThicknessInput - 1) * 0.001)));
    screenPos = screenPos + rimNormals.y * 0.001;

    // sample depth texture again to another object with modified screenPos
    half rimDepth = SampleSceneDepth(screenPos.xy);
     rimDepth = LinearEyeDepth(rimDepth, _ZBufferParams);

    // now compare the two
    half depthDiff = rimDepth - linearDepth;

    // finally, le rim light :)
    half rimLight = saturate(smoothstep(0, 1, depthDiff));
    // creative freedom from here on
    rimLight *= saturate(lerp(1, 0, linearDepth - 8));
    rimLight = rimLight * max(factor * 0.2, 0.1) * RimLightIntensityInput;

    return rimLight;
}

/* https://github.com/penandlim/JL-s-Unity-Blend-Modes/blob/master/John%20Lim's%20Blend% Modes/CGIncludes/PhotoshopBlendModes.cginc */

// color dodge blend mode
vector<half, 3> ColorDodge(const vector<half, 3> s, const vector<half, 3> d){
    return d / (1.0 - min(s, 0.999));
}

vector<half, 4> ColorDodge(const vector<half, 4> s, const vector<half, 4> d){
    return vector<half, 4>(d.xyz / (1.0 - min(s.xyz, 0.999)), d.w);
}

// https://github.com/cnlohr/shadertrixx/blob/main/README.md#detecting-if-you-are-on-desktop-vr-camera-etc
bool isVR(){
    // USING_STEREO_MATRICES
    #if UNITY_SINGLE_PASS_STEREO
        return true;
    #else
        return false;
    #endif
}

// https://gist.github.com/Reedbeta/e8d3817e3f64bba7104b8fafd62906df
// THIS IS NOT SUPPOSED TO BE USED NORMALLY, THE ONLY REASON AS TO WHY THIS IS HERE IS BECAUSE
// MODEL RIPS CAN OCCASIONALLY BE IN .GLTF/.GLB FORMAT WHICH ENFORCES LINEAR VERTEX COLORS, WE
// CAN WORK AROUND THAT IN-SHADER THROUGH THESE FUNCTIONS
vector<float, 3> sRGBToLinear(const vector<float, 3> rgb){
  // See https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
  return lerp(pow((rgb + 0.055) * (1.0 / 1.055), (vector<float, 3>)2.4),
              rgb * (1.0/12.92),
              rgb <= (vector<float, 3>)0.04045);
}

vector<float, 3> LinearToSRGB(const vector<float, 3> rgb){
  // See https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
  return lerp(1.055 * pow(rgb, (vector<float, 3>)(1.0 / 2.4)) - 0.055,
              rgb * 12.92,
              rgb <= (vector<float, 3>)0.0031308);
}

vector<float, 4> VertexColorConvertToLinear(const vector<float, 4> input){
    return vector<float, 4>(sRGBToLinear(input.xyz),
                            input.w); // retain alpha
}

void calculateDissolve(out vector<float, 3> input, vector<float, 2> uvs, float factor){
    float buf2 = 1.0 - uvs.y;
    float buf = (_DissolveDirection_Toggle != 0.0) ? buf2 : uvs.y;
    buf = _WeaponDissolveValue * 2.1 + buf;
    vector<float, 2> dissolveUVs = vector<float, 2>(uvs.x, buf - 1.0); // tmp1.xy

    vector<half, 4> dissolveTex = _WeaponDissolveTex.Sample(sampler_WeaponDissolveTex, dissolveUVs);
    buf = dissolveTex * 3.0 * factor;
    buf = buf * 0.5 + dissolveTex.x;

    input = saturate(vector<float, 3>(buf.x, dissolveTex.y, 0.0));
}

// apache license: https://gitlab.com/s-ilent/filamented/-/blob/master/Filamented/SharedFilteringLib.hlsl
vector<float, 4> cubic(float v){
    vector<float, 4> n = vector<float, 4>(1.0, 2.0, 3.0, 4.0) - v;
    vector<float, 4> s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vector<float, 4>(x, y, z, w);
}

vector<float, 4> SampleTexture2DBicubicFilter(Texture2D tex, SamplerState smp, vector<float, 2> coord, const vector<float, 4> texSize){
    coord = coord * texSize.xy - 0.5;
    float fx = frac(coord.x);
    float fy = frac(coord.y);
    coord.x -= fx;
    coord.y -= fy;

    vector<float, 4> xcubic = cubic(fx);
    vector<float, 4> ycubic = cubic(fy);

    vector<float, 4> c = vector<float, 4>(coord.x - 0.5, coord.x + 1.5, coord.y - 0.5, coord.y + 1.5);
    vector<float, 4> s = vector<float, 4>(xcubic.x + xcubic.y, xcubic.z + xcubic.w, ycubic.x + ycubic.y, ycubic.z + ycubic.w);
    vector<float, 4> offset = c + vector<float, 4>(xcubic.y, xcubic.w, ycubic.y, ycubic.w) / s;

    vector<float, 4> sample0 = tex.Sample(smp, vector<float, 2>(offset.x, offset.z) * texSize.zw);
    vector<float, 4> sample1 = tex.Sample(smp, vector<float, 2>(offset.y, offset.z) * texSize.zw);
    vector<float, 4> sample2 = tex.Sample(smp, vector<float, 2>(offset.x, offset.w) * texSize.zw);
    vector<float, 4> sample3 = tex.Sample(smp, vector<float, 2>(offset.y, offset.w) * texSize.zw);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return lerp(
        lerp(sample3, sample2, sx),
        lerp(sample1, sample0, sx), sy);
}
