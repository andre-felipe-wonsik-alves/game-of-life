#[compute]
#version 450

const vec4 ALIVE = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 DEAD  = vec4(0.0, 0.0, 0.0, 1.0);

layout (local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

layout (set = 0, binding = 0, r8)  uniform readonly  image2D inputImage;
layout (set = 0, binding = 1, r8)  uniform writeonly image2D outputImage;

bool is_alive(int x, int y){
    vec4 p = imageLoad(inputImage, ivec2(x, y));
    return p.r > 0.5;
}

int live_neighbors(int x, int y, ivec2 size){
    int c = 0;
    for (int i = -1; i <= 1; i++){
        for (int j = -1; j <= 1; j++){         
            if(i == 0 && j == 0) continue;
            int nx = x + i, ny = y + j;
            if (nx >= 0 && ny >= 0 && nx < size.x && ny < size.y){
                c += is_alive(nx, ny) ? 1 : 0;
            }
        }
    }
    return c;
}

void main(){
    ivec2 pos  = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(inputImage);
    if (pos.x >= size.x || pos.y >= size.y) return;

    int  n = live_neighbors(pos.x, pos.y, size);
    bool a = is_alive(pos.x, pos.y);
    bool next = a;

    // Regras de Conway
    if (a && (n < 2 || n > 3)) next = false;
    else if (!a && n == 3)     next = true;

    imageStore(outputImage, pos, next ? ALIVE : DEAD);
}
