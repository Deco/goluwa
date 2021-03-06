local PASS = {}

PASS.Name = "light"
PASS.Position = 1

PASS.Variables = {
	ambient_lighting = Color(0.3, 0.3, 0.3, 1),
}
PASS.Source = [[	
	float get_depth(vec2 coord) 
	{
		return (2.0 * cam_nearz) / (cam_farz + cam_nearz - texture(tex_depth, coord).r * (cam_farz - cam_nearz));
	}	
	
	float compare_depths( in float depth1, in float depth2 ) {
		float diff = (depth2)-(depth1-0.000005);
		diff = clamp(diff *= 30000, 0, 0.25);
						
		return diff;
	}
	
	float ssao()
	{

		float depth = get_depth(uv);
		
		if (depth > 0.05) return 1;
		
		float pw = 1.0 / size.x;
		float ph = 1.0 / size.y;

		float ao = 0;
		
		float aoscale = 2.2;
		
		pw /= aoscale;
		ph /= aoscale;
		
		for (int i = 1; i < 5; i++)
		{					
			ao += compare_depths(depth, get_depth(vec2(uv.x+pw,uv.y+ph)));
			ao += compare_depths(depth, get_depth(vec2(uv.x-pw,uv.y+ph)));
			ao += compare_depths(depth, get_depth(vec2(uv.x+pw,uv.y-ph)));
			ao += compare_depths(depth, get_depth(vec2(uv.x-pw,uv.y-ph)));
		 
			pw *= aoscale;
			ph *= aoscale;
		}			 
	 
		ao/=4.0;
	 
		return 0.5+clamp(ao*2, 0, 1)*0.5;
	}
	
	out vec4 out_color;
		
	void main()
	{		
		out_color.rgb = texture(tex_diffuse, uv).rgb;
		out_color.a = 1;
						
		vec3 light = texture(tex_light, uv).rgb;
		if (out_color.rgb != vec3(0,0,0)) light *= ssao();
		//light *= ssao()
		light = max(light, ambient_lighting.rgb);

		out_color.rgb *= light;
	}
]]

render.AddGBufferShader(PASS)