"""把晨的意图图确定性地烘焙为侵蚀高度场；运行环境见 requirements-bake.txt。"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time

import numpy as np
from numba import njit


AXES = np.array([
    [[0, 1, 0], [1, 0, 0], [0, 0, -1]],
    [[0, -1, 0], [1, 0, 0], [0, 0, 1]],
    [[1, 0, 0], [0, 0, -1], [0, 1, 0]],
    [[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
    [[0, 0, 1], [1, 0, 0], [0, 1, 0]],
    [[0, 0, -1], [-1, 0, 0], [0, 1, 0]],
], dtype=np.float64)
RADIUS = 40000.0


@njit(cache=True)
def dot(a, b):
    return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]


@njit(cache=True)
def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


@njit(cache=True)
def direction(face, x, y, n):
    p = AXES[face, 0] + AXES[face, 1] * (2 * x / (n - 1) - 1) + AXES[face, 2] * (2 * y / (n - 1) - 1)
    return p / np.sqrt(dot(p, p))


@njit(cache=True)
def face_uv(p, n):
    a = np.abs(p)
    if a[1] >= a[0] and a[1] >= a[2]:
        f = 0 if p[1] >= 0 else 1
    elif a[0] >= a[2]:
        f = 2 if p[0] >= 0 else 3
    else:
        f = 4 if p[2] >= 0 else 5
    scale = dot(p, AXES[f, 0])
    u = (dot(p, AXES[f, 1]) / scale + 1) * 0.5 * (n - 1)
    v = (dot(p, AXES[f, 2]) / scale + 1) * 0.5 * (n - 1)
    return f, u, v


@njit(cache=True)
def node(h, f, x, y):
    n = h.shape[1]
    if x < 0 or y < 0 or x >= n or y >= n:
        f, u, v = face_uv(direction(f, x, y, n), n)
        x = int(round(u))
        y = int(round(v))
    return h[f, y, x]


@njit(cache=True)
def bilinear(h, f, x, y):
    n = h.shape[1]
    if x < 0 or y < 0 or x > n - 1 or y > n - 1:
        f, x, y = face_uv(direction(f, x, y, n), n)
    ix, iy = int(math.floor(x)), int(math.floor(y))
    tx, ty = x - ix, y - iy
    a, b = node(h, f, ix, iy), node(h, f, ix + 1, iy)
    c, d = node(h, f, ix, iy + 1), node(h, f, ix + 1, iy + 1)
    value = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    return value, (b - a) * (1 - ty) + (d - c) * ty, (c - a) * (1 - tx) + (d - b) * tx


@njit(cache=True)
def hash_value(x, y, z, seed):
    v = (x * 374761393 + y * 668265263 + z * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFFFFFF) / 2147483647.5 - 1.0


@njit(cache=True)
def noise(p, seed):
    ix, iy, iz = int(math.floor(p[0])), int(math.floor(p[1])), int(math.floor(p[2]))
    t = p - np.array([ix, iy, iz])
    w = t * t * t * (t * (t * 6 - 15) + 10)
    dw = 30 * t * t * (t - 1) * (t - 1)
    value, dx, dy, dz = 0.0, 0.0, 0.0, 0.0
    for z in range(2):
        for y in range(2):
            for x in range(2):
                q = hash_value(ix + x, iy + y, iz + z, seed)
                wx, wy, wz = (w[0] if x else 1 - w[0]), (w[1] if y else 1 - w[1]), (w[2] if z else 1 - w[2])
                value += q * wx * wy * wz
                dx += q * (dw[0] if x else -dw[0]) * wy * wz
                dy += q * wx * (dw[1] if y else -dw[1]) * wz
                dz += q * wx * wy * (dw[2] if z else -dw[2])
    return value, np.array([dx, dy, dz])


@njit(cache=True)
def ridges(p, seed):
    warp = np.empty(3)
    for k in range(3):
        warp[k] = noise(p / 4400.0, seed + 29 * k)[0] * 1250.0
    q = p + warp
    result, amplitude, frequency = 0.0, 1.0, 1.0 / 2600.0
    derivative = np.zeros(3)
    for octave in range(5):
        value, gradient = noise(q * frequency, seed + octave * 73)
        ridge = (1.0 - abs(value)) ** 2
        derivative += gradient * (-2 * (1 - abs(value)) * (1 if value > 0 else -1)) * frequency * amplitude * 600.0
        result += (ridge - 0.62) * amplitude / (1.0 + 5.0 * dot(derivative, derivative))
        frequency *= 2.03
        amplitude *= 0.46
    return result


def spline(points, subdivisions=6):
    """在原始布局点之间插值，不移动布局锚点。"""
    p = np.asarray(points, dtype=np.float64)
    result = []
    for i in range(len(p) - 1):
        a, b, c, d = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]
        for t in np.arange(subdivisions) / subdivisions:
            q = b + 0.5 * t * (c - a + t * (2*a - 5*b + 4*c - d + t * (3*(b-c) + d-a)))
            result.append(q / np.linalg.norm(q) * RADIUS)
    result.append(p[-1] / np.linalg.norm(p[-1]) * RADIUS)
    return np.array(result)


@njit(cache=True)
def nearest(p, curve, lengths):
    best, along, side = 1e30, 0.0, 0.0
    for i in range(len(curve) - 1):
        lx, ly, lz = curve[i+1, 0]-curve[i, 0], curve[i+1, 1]-curve[i, 1], curve[i+1, 2]-curve[i, 2]
        px, py, pz = p[0]-curve[i, 0], p[1]-curve[i, 1], p[2]-curve[i, 2]
        t = min(1.0, max(0.0, (px*lx+py*ly+pz*lz)/(lx*lx+ly*ly+lz*lz)))
        dx, dy, dz = px-t*lx, py-t*ly, pz-t*lz
        distance = dx*dx+dy*dy+dz*dz
        if distance < best:
            best = distance
            along = lengths[i] + t * (lengths[i + 1] - lengths[i])
            side = p[0]*(curve[i, 1]*lz-curve[i, 2]*ly)+p[1]*(curve[i, 2]*lx-curve[i, 0]*lz)+p[2]*(curve[i, 0]*ly-curve[i, 1]*lx)
    return math.sqrt(best), along, side


@njit(cache=True)
def build_face(h, f, base, ridge, ridge_len, canyon, canyon_len, peaks, passes, volcano, source_level, seed):
    n = h.shape[1]
    for y in range(n):
        for x in range(n):
            up = direction(f, x, y, n)
            p = up * RADIUS
            value = bilinear(base, f, x / (n - 1) * (base.shape[1] - 1), y / (n - 1) * (base.shape[1] - 1))[0]
            detail = ridges(p, seed)
            value += detail * 160.0 * smooth(100, 600, value)
            dist, along, _ = nearest(p, ridge, ridge_len)
            if dist < 10000:
                envelope = (1.0 - smooth(0, 10000, dist)) ** 1.4
                rise = 1600.0 + 280.0 * math.sin(along / 13000)
                value += envelope * (rise + detail * 1000.0)
                for peak in peaks:
                    delta = p - peak[:3] * RADIUS
                    distance = math.sqrt(dot(delta, delta))
                    target = peak[3]
                    shape = int(peak[4])
                    right, forward = peak[5:8], peak[8:11]
                    if shape == 0:
                        # 不等边金字塔，基部随脊状噪声分裂成支脊。
                        distance = max(abs(dot(delta, right)), abs(dot(delta, forward)) * 1.12, abs(dot(delta, (right+forward)/1.414)) * 0.84)
                    elif shape == 1:
                        a, b = delta - right * 450, delta + right * 450
                        distance = min(math.sqrt(dot(a, a)), math.sqrt(dot(b, b)))
                        target -= 430.0 * (1 - smooth(0, 300, abs(dot(delta, right))))
                    else:
                        distance = max(0.0, distance - 300.0) * 3
                    w = 1 - smooth(0, 2100, distance)
                    value = value * (1-w) + (target - distance * 0.55 + detail * 100 * smooth(0, 500, distance)) * w
                for site in passes:
                    delta = p - site[:3] * RADIUS
                    across = abs(dot(delta, site[6:9]))
                    lateral = abs(dot(delta, site[3:6]))
                    w = (1-smooth(650, 1250, lateral)) * (1-smooth(8500, 10000, across))
                    level = site[9] + 500 * (1-smooth(0, 10000, across))
                    value = value * (1-w) + level * w
            delta = p - volcano[:3] * RADIUS
            distance = math.sqrt(dot(delta, delta))
            if distance < 2500:
                radial_noise = noise(p / 420, seed+503)[0]
                r = distance / (1 + radial_noise * 0.085)
                w = 1 - smooth(1750, 2250, r)
                if r < 280:
                    elevation = 766 - 115 * (1 - (r / 280) ** 2)
                else:
                    elevation = 766 * max(0.0, (2100-r)/1820) ** 1.45
                value = value * (1-w) + (volcano[3] + elevation) * w
            dist, along, side = nearest(p, canyon, canyon_len)
            if dist < 2600:
                t = along / canyon_len[-1]
                floor = source_level * (1-t) ** 5 - t * 2
                depth = (790 + 80 * math.sin(t * math.pi) + 25 * math.sin(t*19)) * smooth(0, 0.12, t) * (1-smooth(0.94, 1, t))
                width = (1170 + 100 * math.sin(t*21) + 80 * noise(p/1300, seed+751)[0]) * (0.88 if side > 0 else 1.1)
                # 主体连续；45 米级的层理由运行时叠加。
                across = min(1.0, max(0.0, (dist-110)/(width-110)))
                wall = across ** (0.9 if side > 0 else 1.25)
                carved = floor + depth * wall
                w = smooth(width, width+900, dist)
                value = carved * (1-w) + value * w
            h[f, y, x] = value


@njit(cache=True)
def reconcile(h):
    """同一物理棱共享一个高度；不用各面单独钳制边缘。"""
    n = h.shape[1]
    for f in range(6):
        for edge in range(4):
            for i in range(n):
                x = i if edge < 2 else (0 if edge == 2 else n-1)
                y = (0 if edge == 0 else n-1) if edge < 2 else i
                p = direction(f, x, y, n)
                for other in range(f+1, 6):
                    d = dot(p, AXES[other, 0])
                    if d <= 0:
                        continue
                    u, v = dot(p, AXES[other, 1])/d, dot(p, AXES[other, 2])/d
                    if abs(u) <= 1.00000001 and abs(v) <= 1.00000001:
                        ox, oy = int(round((u+1)*0.5*(n-1))), int(round((v+1)*0.5*(n-1)))
                        value = (h[f, y, x] + h[other, oy, ox]) * 0.5
                        h[f, y, x] = value
                        h[other, oy, ox] = value


@njit(cache=True)
def deposit(h, f, x, y, amount):
    n = h.shape[1]
    ix, iy = int(math.floor(x)), int(math.floor(y))
    tx, ty = x-ix, y-iy
    for j in range(2):
        for i in range(2):
            xx, yy, ff = ix+i, iy+j, f
            if xx < 0 or yy < 0 or xx >= n or yy >= n:
                ff, u, v = face_uv(direction(f, xx, yy, n), n)
                xx, yy = int(round(u)), int(round(v))
            h[ff, yy, xx] += amount * (tx if i else 1-tx) * (ty if j else 1-ty)


@njit(cache=True)
def erode(h, f, x, y, amount):
    # 三格圆形刷子按权重守恒移走物质，避免单格针孔。
    n = h.shape[1]
    ix, iy = int(x), int(y)
    total = 0.0
    for j in range(-2, 4):
        for i in range(-2, 4):
            total += max(0.0, 3-math.sqrt((ix+i-x)**2+(iy+j-y)**2))
    for j in range(-2, 4):
        for i in range(-2, 4):
            w = max(0.0, 3-math.sqrt((ix+i-x)**2+(iy+j-y)**2)) / total
            if w == 0:
                continue
            xx, yy, ff = ix+i, iy+j, f
            if xx < 0 or yy < 0 or xx >= n or yy >= n:
                ff, u, v = face_uv(direction(f, xx, yy, n), n)
                xx, yy = int(round(u)), int(round(v))
            h[ff, yy, xx] -= amount * w


@njit(cache=True)
def hydraulic(h, droplets, steps, seed):
    n = h.shape[1]
    state = seed
    removed, deposited, crossed = 0.0, 0.0, 0
    for start_face in range(6):
        for drop in range(droplets):
            state = (1664525 * state + 1013904223) & 0xFFFFFFFF
            x = (state / 4294967296.0) * (n-1)
            state = (1664525 * state + 1013904223) & 0xFFFFFFFF
            y = (state / 4294967296.0) * (n-1)
            f, dx, dy, speed, water, sediment = start_face, 0.0, 0.0, 1.0, 1.0, 0.0
            for _ in range(steps):
                old, gx, gy = bilinear(h, f, x, y)
                if old < 0:
                    break
                dx, dy = dx * 0.18 - gx * 0.82, dy * 0.18 - gy * 0.82
                length = math.sqrt(dx*dx + dy*dy)
                if length < 1e-12:
                    break
                dx, dy = dx/length, dy/length
                nx, ny, nf = x+dx, y+dy, f
                if nx < 0 or ny < 0 or nx > n-1 or ny > n-1:
                    # 跨面后转换速度方向；水滴继续运动，不在棱上蒸发或停止。
                    point = direction(f, nx, ny, n)
                    nf, nx, ny = face_uv(point, n)
                    _, tx, ty = face_uv(point + (AXES[f, 1]*dx+AXES[f, 2]*dy)*0.00001, n)
                    dx, dy = tx-nx, ty-ny
                    crossed += 1
                new = bilinear(h, nf, nx, ny)[0]
                delta = new-old
                capacity = max(min(-delta * speed * water * 4.0, 40.0), 0.1)
                if sediment > capacity or delta > 0:
                    amount = min(delta, sediment) if delta > 0 else (sediment-capacity)*0.25
                    deposit(h, f, x, y, amount)
                    sediment -= amount
                    deposited += amount
                else:
                    amount = min((capacity-sediment)*0.3, max(0.0, -delta), 35.0)
                    erode(h, f, x, y, amount)
                    sediment += amount
                    removed += amount
                speed = math.sqrt(max(0.0, speed*speed-delta*0.15))
                water *= 0.985
                f, x, y = nf, nx, ny
            # 留在陆地的悬沙沉积，进入海洋的部分构成河口沉积。
            if sediment > 0:
                erode(h, f, x, y, -sediment)
                deposited += sediment
    return removed, deposited, crossed


@njit(cache=True)
def neighbor_cell(cell, ox, oy, n):
    f, y, x = cell//(n*n), (cell//n)%n, cell%n
    x, y = x+ox, y+oy
    if x < 0 or y < 0 or x >= n or y >= n:
        f, u, v = face_uv(direction(f, x, y, n), n)
        x, y = int(round(u)), int(round(v))
    return canonical_cell(f*n*n+y*n+x, n)


@njit(cache=True)
def canonical_cell(cell, n):
    f, y, x = cell//(n*n), (cell//n)%n, cell%n
    if x == 0 or y == 0 or x == n-1 or y == n-1:
        f, u, v = face_uv(direction(f, x, y, n), n)
        return f*n*n+int(round(v))*n+int(round(u))
    return cell


@njit(cache=True)
def drainage(h):
    """优先填洼消除侵蚀造成的孤立小坑，保留面积和深度足够的天然湖盆。"""
    n, count = h.shape[1], h.size
    original = h.ravel()
    filled = original.copy()
    seen = np.zeros(count, dtype=np.uint8)
    parent = np.full(count, -1, dtype=np.int32)
    queue = np.empty(count, dtype=np.int32)
    heap_ids = np.empty(count, dtype=np.int32)
    heap_keys = np.empty(count, dtype=np.float32)
    order = np.empty(count, dtype=np.int32)
    head, tail, heap_size, rank = 0, 0, 0, 0
    for cell in range(count):
        if original[cell] < 0 and canonical_cell(cell, n) == cell:
            queue[tail] = cell
            tail += 1
            seen[cell] = 1
    while head < tail or heap_size:
        if head < tail:
            cell = queue[head]
            head += 1
        else:
            cell = heap_ids[0]
            heap_size -= 1
            value, key = heap_ids[heap_size], heap_keys[heap_size]
            cursor = 0
            while cursor*2+1 < heap_size:
                child = cursor*2+1
                if child+1 < heap_size and heap_keys[child+1] < heap_keys[child]:
                    child += 1
                if heap_keys[child] >= key:
                    break
                heap_keys[cursor], heap_ids[cursor] = heap_keys[child], heap_ids[child]
                cursor = child
            heap_keys[cursor], heap_ids[cursor] = key, value
        order[rank] = cell
        rank += 1
        for oy in range(-1, 2):
            for ox in range(-1, 2):
                if ox == 0 and oy == 0:
                    continue
                other = neighbor_cell(cell, ox, oy, n)
                if seen[other]:
                    continue
                seen[other] = 1
                parent[other] = cell
                # 队列加速只适用于同一水位；微小出水坡度在填洼结束后沿父链建立。
                level = max(0.0, filled[cell])
                if original[other] <= level:
                    filled[other] = level
                    queue[tail] = other
                    tail += 1
                else:
                    cursor, key = heap_size, original[other]
                    heap_size += 1
                    while cursor > 0:
                        above = (cursor-1)//2
                        if heap_keys[above] <= key:
                            break
                        heap_keys[cursor], heap_ids[cursor] = heap_keys[above], heap_ids[above]
                        cursor = above
                    heap_keys[cursor], heap_ids[cursor] = key, other
    # 湖盆以连续湿润区域判定，不把每个一格小坑命名为湖。
    wet = (filled-original > 0.1) & (original >= 0)
    for cell in range(count):
        shared = canonical_cell(cell, n)
        if shared != cell:
            parent[cell] = shared
            wet[cell] = False
    lake = np.zeros(count, dtype=np.uint8)
    seen[:] = 0
    lakes = 0
    for start in range(count):
        if not wet[start] or seen[start]:
            continue
        head, tail, area, depth = 0, 1, 0.0, 0.0
        queue[0], seen[start] = start, 1
        while head < tail:
            cell = queue[head]
            head += 1
            u, v = 2*(cell%n)/(n-1)-1, 2*((cell//n)%n)/(n-1)-1
            area += (2*RADIUS/(n-1))**2/(1+u*u+v*v)**1.5
            depth = max(depth, filled[cell]-original[cell])
            for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                other = neighbor_cell(cell, ox, oy, n)
                if wet[other] and not seen[other] and abs(filled[other]-filled[start]) < 0.01:
                    seen[other] = 1
                    queue[tail] = other
                    tail += 1
        if area >= 120000 and depth >= 4:
            lakes += 1
            for i in range(tail):
                lake[queue[i]] = 1
    for cell in range(count):
        if not lake[cell]:
            original[cell] = filled[cell]
    for index in range(rank):
        cell = order[index]
        above = parent[cell]
        if above >= 0 and not lake[cell] and not lake[above] and original[cell] >= 0:
            original[cell] = max(original[cell], original[above]+0.08)
    # 棱和角上的副本共用同一个拓扑节点，不能在填洼后各自平均出新的小坑。
    for cell in range(count):
        shared = canonical_cell(cell, n)
        if shared != cell:
            original[cell] = original[shared]
            lake[cell] = lake[shared]
    return lake.reshape(h.shape), parent, lakes


@njit(cache=True)
def protect_drainage(h, original, parent, lake, spawn):
    """恢复原地形保护区，并检查新生成部分的每条出水边。"""
    grid = h.shape[1]
    flat = h.ravel()
    mask = lake.ravel()
    original_flat = original.ravel()
    boundary = math.cos(2020.0/RADIUS)
    protected = np.zeros(h.size, dtype=np.uint8)
    for cell in range(h.size):
        face = cell//(grid*grid)
        if dot(direction(face, cell % grid, (cell//grid) % grid, grid), spawn) >= boundary:
            protected[cell] = 1
            flat[cell] = original_flat[cell]
    uphill, roots, retained, checked = 0, 0, 0, 0
    for cell in range(h.size):
        if flat[cell] < 0 or mask[cell]:
            continue
        above = parent[cell]
        invalid = above < 0 or flat[above] > flat[cell]+0.001
        if protected[cell]:
            retained += int(invalid)
        else:
            checked += 1
            roots += int(above < 0)
            uphill += int(above >= 0 and invalid)
    return checked, uphill, roots, retained


@njit(cache=True)
def thermal(h, canyon, canyon_len, peaks, iterations):
    n = h.shape[1]
    collapse = np.zeros_like(h)
    for _ in range(iterations):
        delta = np.zeros_like(h)
        for f in range(6):
            for y in range(n):
                for x in range(n):
                    value = h[f, y, x]
                    best, bx, by = 0.0, x, y
                    step = 2*RADIUS/(n-1) / math.sqrt(1+(2*x/(n-1)-1)**2+(2*y/(n-1)-1)**2)
                    for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        drop = value-node(h, f, x+ox, y+oy)-step*math.tan(math.radians(35))
                        if drop > best:
                            best, bx, by = drop, x+ox, y+oy
                    if best <= 0:
                        continue
                    p = direction(f, x, y, n) * RADIUS
                    distance, along, _ = nearest(p, canyon, canyon_len)
                    hardness = 1.0
                    if distance < 1500:
                        # 少量软岩区允许坍塌，和运行时台阶共用该结果。
                        hardness = 0.08 + 0.65 * smooth(0.55, 0.8, noise(p/850, 421)[0])
                    for peak in peaks:
                        d = p-peak[:3]*RADIUS
                        if dot(d, d) < 1600**2:
                            hardness = min(hardness, 0.06)
                    amount = best * 0.2 * hardness
                    ff = f
                    if bx < 0 or by < 0 or bx >= n or by >= n:
                        ff, u, v = face_uv(direction(f, bx, by, n), n)
                        bx, by = int(round(u)), int(round(v))
                    delta[f, y, x] -= amount
                    delta[ff, by, bx] += amount
                    collapse[f, y, x] += amount
        h += delta
        reconcile(h)
    return collapse


@njit(cache=True)
def resample(h, size):
    result = np.empty((6, size, size), dtype=np.float32)
    for f in range(6):
        for y in range(size):
            for x in range(size):
                result[f, y, x] = bilinear(h, f, x/(size-1)*(h.shape[1]-1), y/(size-1)*(h.shape[1]-1))[0]
    return result


@njit(cache=True)
def apply_thermal_delta(h, change):
    n = h.shape[1]
    for f in range(6):
        for y in range(n):
            for x in range(n):
                h[f, y, x] += bilinear(change, f, x/(n-1)*(change.shape[1]-1), y/(n-1)*(change.shape[1]-1))[0]


@njit(cache=True)
def cubic(a, b, c, d, t):
    return b+0.5*t*(c-a+t*(2*a-5*b+4*c-d+t*(3*(b-c)+d-a)))


@njit(cache=True)
def anchor_spawn(h, spawn, original):
    n = h.shape[1]
    f, x, y = face_uv(spawn, n)
    ix, iy, tx, ty = int(x), int(y), x-int(x), y-int(y)
    rows = np.empty(4)
    for j in range(4):
        rows[j] = cubic(node(h, f, ix-1, iy+j-1), node(h, f, ix, iy+j-1), node(h, f, ix+1, iy+j-1), node(h, f, ix+2, iy+j-1), tx)
    correction = original-cubic(rows[0], rows[1], rows[2], rows[3], ty)
    for yy in range(max(0, iy-20), min(n, iy+21)):
        for xx in range(max(0, ix-20), min(n, ix+21)):
            delta = direction(f, xx, yy, n)-spawn
            distance = math.sqrt(dot(delta, delta))*RADIUS
            h[f, yy, xx] += correction*(1-smooth(0, 300, distance))


@njit(cache=True)
def protect(h, patch, spawn, forward, right, patch_step):
    n, size = h.shape[1], patch.shape[1]
    for f in range(6):
        for y in range(n):
            for x in range(n):
                up = direction(f, x, y, n)
                distance = math.sqrt(dot(up-spawn, up-spawn))*RADIUS
                if distance >= 3000:
                    continue
                scale = RADIUS/dot(up, spawn)
                px = dot(up, right)*scale/patch_step+(size-1)/2
                py = dot(up, forward)*scale/patch_step+(size-1)/2
                original = bilinear(patch, 0, px, py)[0]
                w = smooth(2020, 3000, distance)
                h[f, y, x] = original*(1-w)+h[f, y, x]*w


@njit(cache=True)
def bordered(h, f):
    n = h.shape[1]
    result = np.empty((n+4, n+4), dtype=np.float32)
    for y in range(n+4):
        for x in range(n+4):
            result[y, x] = bilinear(h, f, x-2.0, y-2.0)[0]
    return result


def curve_lengths(curve):
    return np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(curve, axis=0), axis=1))]


def write_spawn_patch(patch, meta, output):
    # 独立保留八米采样，避免三十一米全局格距损失出生区细节。
    encoded = np.rint((np.clip(patch, -500, 4300)+500)/4800*65535).astype('<u2')
    encoded.tofile(output/'spawn-original.u16')
    return dict(meta['spawn_patch'], direction=meta['landforms']['spawn'], sha256=hashlib.sha256(encoded.tobytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--intent', type=Path, default=Path('test-output/terrain/intent'))
    parser.add_argument('--output', type=Path, default=Path('test-output/terrain/baked'))
    parser.add_argument('--grid', type=int, default=2048)
    parser.add_argument('--droplets', type=int, default=500000, help='每个面的水滴数量')
    parser.add_argument('--steps', type=int, default=80)
    parser.add_argument('--thermal-iterations', type=int, default=12)
    parser.add_argument('--seed', type=int, default=20261019)
    parser.add_argument('--godot', type=Path)
    args = parser.parse_args()
    if args.grid < 128 or args.grid % 4 or args.droplets <= 0:
        parser.error('格网至少 128 且为 4 的倍数，水滴数量必须大于零')
    started = time.perf_counter()
    meta = json.loads((args.intent/'layout.json').read_text(encoding='utf-8'))
    signature = hashlib.sha256()
    stable = {k: v for k, v in meta.items() if k != 'export_seconds'}
    signature.update(json.dumps(stable, sort_keys=True).encode())
    for path in sorted(args.intent.glob('*.f32')):
        signature.update(path.name.encode())
        signature.update(path.read_bytes())
    size = meta['grid']
    base = np.stack([np.fromfile(args.intent/f'base-{f}.f32', dtype='<f4').reshape(size, size) for f in range(6)])
    forms = meta['landforms']
    ridge, canyon = spline(forms['ridge']), spline(forms['canyon'])
    ridge_len, canyon_len = curve_lengths(ridge), curve_lengths(canyon)
    peaks = np.array([p['direction']+[p['height'], ['horn', 'twins', 'mesa'].index(p['shape'])]+p['right']+p['forward'] for p in forms['peaks']], dtype=np.float64)
    passes = np.array([p['direction']+p['along']+p['across']+[p['ground']] for p in forms['passes']], dtype=np.float64)
    v = np.array(meta['volcano'])/RADIUS
    volcano = np.array(meta['center'])*math.sqrt(1-float(np.dot(v,v)))+np.array(meta['axis_u'])*v[0]+np.array(meta['axis_v'])*v[1]
    volcano = np.r_[volcano/np.linalg.norm(volcano), meta['volcano_base']]
    h = np.empty((6, args.grid, args.grid), dtype=np.float32)
    times = {}
    for f in range(6):
        phase = time.perf_counter()
        build_face(h, f, base, ridge, ridge_len, canyon, canyon_len, peaks, passes, volcano, forms['canyon_source_level'], args.seed)
        print(f'高度生成 {f+1}/6：{time.perf_counter()-phase:.1f} 秒', flush=True)
    reconcile(h)
    times['shape'] = time.perf_counter()-started
    phase = time.perf_counter()
    amounts = hydraulic(h, args.droplets, args.steps, args.seed)
    reconcile(h)
    times['hydraulic'] = time.perf_counter()-phase
    print(f'水力侵蚀：{times["hydraulic"]:.1f} 秒，跨面 {amounts[2]} 次', flush=True)
    phase = time.perf_counter()
    # 粗网格搬运山坡物质，细网格保留沟槽；仅用细格扩散难以在合理时间内稳定公里长坡。
    for level, iterations in ((128, 96), (256, 80), (512, 64)):
        if level >= args.grid:
            continue
        coarse = resample(h, level)
        original_coarse = coarse.copy()
        thermal(coarse, canyon, canyon_len, peaks, iterations)
        apply_thermal_delta(h, coarse-original_coarse)
        reconcile(h)
    collapsed = thermal(h, canyon, canyon_len, peaks, args.thermal_iterations)
    times['thermal'] = time.perf_counter()-phase
    print(f'热力侵蚀：{times["thermal"]:.1f} 秒', flush=True)
    phase = time.perf_counter()
    lake, parent, lake_count = drainage(h)
    reconcile(h)
    times['drainage'] = time.perf_counter()-phase
    print(f'汇水整理：{times["drainage"]:.1f} 秒，保留湖盆 {lake_count} 个', flush=True)
    psize = meta['spawn_patch']['size']
    patch = np.fromfile(args.intent/'spawn-original.f32', dtype='<f4').reshape(1, psize, psize)
    protect(h, patch, np.array(forms['spawn']), np.array(meta['spawn_patch']['forward']), np.array(meta['spawn_patch']['right']), meta['spawn_patch']['step'])
    anchor_spawn(h, np.array(forms['spawn']), patch[0, psize//2, psize//2])
    reconcile(h)
    # 保护区混合会改变局部流向，必须在最终混合之后再次建立出水坡度。
    # 两公里原地形优先保留，不能为消除旧地形的小洼地而突破一米容差。
    phase = time.perf_counter()
    protected_original = h.copy()
    lake, parent, lake_count = drainage(h)
    flow_counts = protect_drainage(h, protected_original, parent, lake, np.array(forms['spawn']))
    reconcile(h)
    times['protected_drainage'] = time.perf_counter()-phase
    drainage_report = dict(zip(('generated_land_cells', 'generated_uphill_edges', 'generated_land_roots', 'preserved_legacy_edges'), map(int, flow_counts)))
    if drainage_report['generated_uphill_edges'] or drainage_report['generated_land_roots']:
        raise RuntimeError(f'新生成区域汇水检查失败：{drainage_report}')
    args.output.mkdir(parents=True, exist_ok=True)
    raw_hash = hashlib.sha256()
    for f in range(6):
        values = bordered(h, f)
        encoded = np.rint((np.clip(values, -500, 4300)+500)/4800*65535).astype('<u2')
        encoded.tofile(args.output/f'height-{f}.u16')
        raw_hash.update(encoded.tobytes())
        loss = collapsed[f].reshape(args.grid//4, 4, args.grid//4, 4).mean(axis=(1, 3))
        np.rint(np.clip(loss/15, 0, 1)*255).astype('u1').tofile(args.output/f'collapse-{f}.u8')
    # 浮点中间高度留在忽略目录，供坡度、侵蚀及汇水检查读取。
    np.save(args.output/'height.npy', h)
    np.save(args.output/'lake-mask.npy', lake)
    np.save(args.output/'drainage-parent.npy', parent)
    parameters = {'grid': args.grid, 'droplets_per_face': args.droplets, 'steps': args.steps, 'thermal_iterations': args.thermal_iterations, 'thermal_levels': [[128, 96], [256, 80], [512, 64]], 'seed': args.seed, 'inertia': 0.18, 'capacity': 4.0, 'maximum_sediment': 40.0, 'erosion': 0.3, 'deposition': 0.25, 'evaporation': 0.015, 'brush_radius_cells': 3, 'talus_degrees': 35, 'drainage_epsilon_m': 0.08}
    report = {'version': 1, 'grid': args.grid, 'minimum': -500, 'maximum': 4300, 'intent_sha256': signature.hexdigest(), 'height_sha256': raw_hash.hexdigest(), 'algorithm_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'parameters': parameters, 'drainage': drainage_report, 'lake_basins': lake_count, 'seconds': times, 'total_seconds': time.perf_counter()-started, 'height_min_m': float(h.min()), 'height_max_m': float(h.max()), 'eroded_m_cells': amounts[0], 'deposited_m_cells': amounts[1], 'cross_face_droplet_steps': amounts[2]}
    report['spawn_patch'] = write_spawn_patch(patch, meta, args.output)
    (args.output/'metadata.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False), flush=True)
    if args.godot:
        root = Path(__file__).resolve().parent.parent
        subprocess.run([str(args.godot), '--headless', '--path', str(root/'game'), '--script', 'res://scripts/tools/terrain_pack.gd', '--', '--check=terrain-pack', f'--terrain-input={args.output.resolve().as_posix()}'], check=True)


if __name__ == '__main__':
    main()
