struct appdata{
    vector<float, 4> vertex : POSITION;
    vector<float, 3> normal : NORMAL;
    vector<float, 2> uv0 : TEXCOORD0;
    vector<float, 2> uv1 : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f{
    vector<float, 4> pos : SV_POSITION;
    vector<float, 4> uv : TEXCOORD0;
    vector<float, 4> vertexOS : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID 
    UNITY_VERTEX_OUTPUT_STEREO
};

float4 GetShadowPositionHClip(appdata v)
{
    float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
    float3 normalWS = TransformObjectToWorldNormal(v.normal);

    #if _CASTING_PUNCTUAL_LIGHT_SHADOW
        float3 lightDirectionWS = normalize(_LightPosition - positionWS);
    #else
        float3 lightDirectionWS = _LightDirection;
    #endif

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    positionCS = ApplyShadowClamping(positionCS);
    return positionCS;
}

v2f vert(appdata v) {
    v2f o = (v2f)0;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    
    o.uv.xy = v.uv0;
    o.uv.zw = v.uv1;
    o.vertexOS = v.vertex;
    o.pos = GetShadowPositionHClip(v);
    
    return o;
}

vector<float, 4> frag (v2f i) : SV_Target{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    // sample textures to objects
    vector<half, 4> mainTex = _MainTex.Sample(sampler_MainTex, vector<half, 2>(i.uv.xy));

    /* WEAPON */

    if(_UseWeapon != 0.0){
        vector<half, 2> weaponUVs = (_ProceduralUVs != 0.0) ? (i.vertexOS.zx + 0.25) * 1.5 : i.uv.zw;

        vector<half, 3> dissolve = 0.0;

        /* DISSOLVE */

        calculateDissolve(dissolve, weaponUVs.xy, 1.0);

        /*buf = dissolveTex < 0.99;

        dissolveTex.x -= 0.001;
        dissolveTex.x = dissolveTex.x < 0.0;
        dissolveTex.x = (buf) ? dissolveTex.x : 0.0;*/

        /* END OF DISSOLVE */

        // apply dissolve
        //globalOutlineColor.w = dissolve.x;
        clip(dissolve.x - _ClipAlphaThreshold);
    }

    /* END OF WEAPON */


    /* CUTOUT TRANSPARENCY */

    if(_MainTexAlphaUse == 1.0) clip(mainTex.w - 0.03 - _MainTexAlphaCutoff);

    /* END OF CUTOUT TRANSPARENCY */


    return 0;
}
