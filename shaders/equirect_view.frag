#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform float uYaw;
uniform float uPitch;
uniform float uFov;
uniform vec2 uTextureSize;
uniform sampler2D uTexture;
out vec4 fragColor;
const float pi = 3.141592653589793;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float scale = tan(uFov * pi / 360.0);
  vec3 d = normalize(vec3((uv.x * 2.0 - 1.0) * scale,
      (1.0 - uv.y * 2.0) * scale * uSize.y / uSize.x, 1.0));
  float p = uPitch * pi / 180.0;
  float y = d.y * cos(p) + d.z * sin(p);
  float z = d.z * cos(p) - d.y * sin(p);
  float a = uYaw * pi / 180.0;
  d = vec3(d.x * cos(a) + z * sin(a), y, z * cos(a) - d.x * sin(a));
  vec2 e = vec2(fract(atan(d.x, d.z) / (2.0 * pi) + 0.5),
      clamp(0.5 - asin(clamp(d.y, -1.0, 1.0)) / pi, 0.5/uTextureSize.y, 1.0-0.5/uTextureSize.y));
  // Blend across the horizontal wrap even with a clamp-mode image sampler.
  float px = e.x * uTextureSize.x - 0.5;
  float left = floor(px);
  float f = fract(px);
  float u0 = (mod(left, uTextureSize.x) + 0.5) / uTextureSize.x;
  float u1 = (mod(left + 1.0, uTextureSize.x) + 0.5) / uTextureSize.x;
  fragColor = mix(texture(uTexture, vec2(u0, e.y)), texture(uTexture, vec2(u1, e.y)), f);
}
