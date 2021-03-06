#version 430 core

layout(binding = 0, rgba32f) uniform image2D framebuffer;

uniform vec3 eye;
uniform vec3 direction;
uniform int sampleCount;
uniform int fov;
uniform int reflectionLimit;
uniform float time;

struct object
{
    int type;

    vec3 pos;
    float radius;
    vec3 color;
};
const float FLT_MAX = 2139095039;

#define TYPE_SPHERE 1
#define TYPE_PLANE 2

#define PI 3.1415926

const object objects[] =
{
    // colors from RaytracerGame.cs
    /* floor */
    {TYPE_PLANE, vec3(0, 1, 0), 0, vec3(163 / 255.0, 68 / 255.0, 0)},
    {TYPE_SPHERE, vec3(0, 2, 0), 2, vec3(54 / 255.0, 210 / 255.0, 21 / 255.0)},
    {TYPE_SPHERE, vec3(3, 2, 0), 1, vec3(31 / 255.0, 81 / 255.0, 167 / 255.0)},
    {TYPE_SPHERE, vec3(-2, 1.5, -2), 0.75, vec3(1, 168 / 255.0, 106 / 255.0)},
    {TYPE_SPHERE, vec3(-4, 1.5, -4), 1, vec3(1, 168 / 255.0, 106 / 255.0)}
};

struct Light
{
    vec3 pos;
    float intensity;
    vec3 color;
};

struct RaytraceResult
{
    vec3 color;
    vec3 intersectPos;
    vec3 dir;
    bool empty;
};

const Light lights[] =
{
    {vec3(0, 5, -3), 1, vec3(250 / 255.0, 1, 219 / 255.0)},
    {vec3(0, 5, -3), 1, vec3(250 / 255.0, 1, 219 / 255.0)}
};

struct hitinfo
{
    int index;
    float distance;
    vec3 normal;
};

float intersectPlane(
        /* ray */
        vec3 origin, vec3 dir,
        /* plane */
        vec3 normal, float d)
{
    float num = dot(dir, normal);
    if (num > -0.00001 && num < 0.00001)
    {
        return -1;
    }
    float dist = (-d - dot(normal, origin)) / num;
    if (dist < 0)
    {
        if (dist < -0.0001)
            return -1;
        return 0;
    }
    return dist;
}

float intersectSphere(
        /* ray */
        vec3 origin, vec3 dir,
        /* sphere */
        vec3 pos, float radius)
{
    vec3 v = pos - origin;
    float lenSq = v.x*v.x + v.y*v.y + v.z*v.z;
    float rSq = radius * radius;
    if (lenSq < rSq)
    {
        // inside sphere
        return 1.0;
    }
    float d = dot(dir, v);
    if (d <= 0)
    {
        // sphere behind origin
        return -1.0;
    }
    // check if radius + ray direction is greater than camera/sphere distance -> intersection
    float x = rSq + d*d - lenSq;
    if (x < 0.0)
    {
        return -1.0;
    }
    // return actual distance from camera
    return d - sqrt(x);
}

bool intersects(vec3 origin, vec3 dir, out hitinfo info)
{
    float smallest = FLT_MAX;
    bool found = false;
    for (int i = 0; i < objects.length; i++)
    {
        if (objects[i].type == TYPE_PLANE)
        {
            // abusing similarity of sphere and plane
            // to store different types of data in same fields
            vec3 normal = objects[i].pos;
            float planeD = objects[i].radius;
            float d = intersectPlane(origin, dir, normal, planeD);
            if (d >= 0.0 && d < smallest)
            {
                info.index = i;
                info.normal = objects[i].pos;
                smallest = d;
                found = true;
            }
        }
        else if (objects[i].type == TYPE_SPHERE)
        {
            vec3 pos = objects[i].pos;
            // HACKY way to get movement going..
            if (i == 4)
            {
                // rotate around center
                float period = 0.1;
                float c = cos(pos.x * PI * time * period);
                float s = sin(pos.z * PI * time * period);
                pos.xz = vec2(c * pos.x - s * pos.z, s * pos.x + c * pos.z);
            }
            else
            {
                // bob up and down
                float amplitude = (i * 0.7) / i;
                // don't want sphere in center (idx 1) to move at all
                float period = (1 - i) * 0.45;
                float offset = sin(PI * time * period) * amplitude;
                pos.y += offset;
            }
            float dist = intersectSphere(origin, dir, pos, objects[i].radius);
            if (dist >= 0.0 && dist < smallest)
            {
                info.index = i;
                vec3 intersectPos = origin + dir * dist;
                info.normal = normalize(intersectPos - pos);
                smallest = dist;
                found = true;
            }
        }
    }
    info.distance = smallest;
    return found;
}

vec3 specular(vec3 pos)
{
    return vec3(0.1);
}

vec3 diffuse(vec3 pos, vec3 surfaceColor)
{
    return surfaceColor;
}

float rnd(int state)
{
    return fract(sin(state));
}

vec3 naturalColor(vec3 pos, vec3 normal, int sampleIndex, vec3 surfaceColor)
{
    vec3 color = vec3(0.2);
    for (int i = 0; i < lights.length; i++)
    {
        vec3 offset = vec3(0);
        if (sampleIndex > 0)
        {
            const float offsetFactor = 0.00001;
            offset = vec3(
                -offsetFactor + 2.0 * rnd(sampleIndex),
                -offsetFactor + 2.0 * rnd(sampleIndex >> 3),
                -offsetFactor + 2.0 * rnd(sampleIndex << 3)
            );
        }
        vec3 d = lights[i].pos + offset - pos;
        vec3 lightDir = normalize(d);
        hitinfo ix;
        if (intersects(pos + lightDir * 0.001, lightDir, ix))
        {
            bool isInShadow = ix.distance * ix.distance < d.x*d.x + d.y*d.y + d.z*d.z;
            if (isInShadow)
                continue;
        }
        float illumination = clamp(dot(lightDir, normal), 0, FLT_MAX);
        vec3 c = illumination * lights[i].color * lights[i].intensity;
        color += c * diffuse(pos, surfaceColor);

        float shininess = 0.4545;
        // TODO: bug in C# code?
        float spec = illumination;
        color += spec * c * pow(spec, shininess) * specular(pos);
    }
    return color / lights.length;
}

RaytraceResult calcForRay(vec3 origin, vec3 dir, int depth, int sampleIndex)
{
    hitinfo i;
    if (intersects(origin, dir, i))
    {
        vec3 intersectPos = origin + dir * i.distance;
        object o = objects[i.index];
        vec3 color = vec3(0);
        vec3 normal = i.normal;
        vec3 cx = o.type == TYPE_SPHERE ? o.color :
            (int(intersectPos.x) + int(intersectPos.z)) % 2 == 0
            ? o.color + vec3(0.3, 0.2, 0.1) : o.color;
        color += naturalColor(intersectPos, normal, sampleIndex, cx);
        if (depth >= reflectionLimit)
        {
            color *= 0.5;
            return RaytraceResult(color, vec3(0), vec3(0), false);
        }
        vec3 reflectDir = dir - 2.0 * dot(normal, dir) * normal;
        return RaytraceResult(color, intersectPos + reflectDir * 0.001, normalize(reflectDir), false);
    }
    return RaytraceResult(vec3(0), vec3(0), vec3(0), true);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main(void)
{
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(framebuffer);
    if (pix.x >= size.x || pix.y >= size.y)
    {
        return;
    }

    // copied from FpsCamera.cs
    float aspect = size.x / float(size.y);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), direction)) * aspect;
    vec3 up = normalize(cross(direction, right));
    float fovAdjust = 1.0 / tan(fov / 2.0 * (PI / 180.0));
    float xoff = -1.0 + ((float(pix.x) / float(size.x - 1.0)) * 2.0);
    float yoff = 1.0 - ((float(pix.y) / float(size.y - 1.0)) * 2.0);
    vec3 dir = direction + (xoff * fovAdjust * right) + (yoff * fovAdjust * up);

    dir = normalize(dir);
    vec3 color = vec3(0);
    int sum = 0;
    for (int i = 0; i < sampleCount; i++)
    {
        RaytraceResult result = {vec3(0), eye, dir, false};
        for (int r = 0; r < reflectionLimit + 1; r++)
        {
            result = calcForRay(result.intersectPos, result.dir, r, i);
            if (result.empty)
                break;

                sum++;
            color += clamp(result.color, vec3(0), vec3(1));
        }
    }
    color /= sum;
    imageStore(framebuffer, pix, vec4(color, 1));
}
