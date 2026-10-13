class_name TerrainMap
extends RefCounted
## Terreno do capítulo: uma grade de 1 m sobre o tabuleiro de 32 × 18 m.
##
## Cada célula é um caractere (é assim que o mapa fica gravado na aventura, uma linha por fileira):
##   "."  chão
##   "#"  parede ou rocha          — bloqueia passagem e visão
##   "T"  coluna, árvore, poste    — bloqueia passagem e visão (ocupa só a célula)
##   "o"  obstáculo baixo          — bloqueia passagem, NÃO bloqueia visão, dá meia cobertura
##   "~"  terreno difícil          — passa, custa o dobro (lama, mato, entulho)
##   "_"  vão: água funda, abismo  — bloqueia passagem, NÃO bloqueia visão
##
## Tudo aqui é em METROS (1 célula = 1 m). O Game converte das posições normalizadas.
## Um TerrainMap vazio (cenas antigas, como a vale_cinzento) deixa tudo livre: o comportamento
## antigo continua idêntico, sem parede nem cobertura.

const FLOOR := 46   # .
const WALL := 35    # #
const PILLAR := 84  # T
const LOW := 111    # o
const ROUGH := 126  # ~
const GAP := 95     # _

const COVER_NONE := 0
const COVER_HALF := 2
const COVER_THREE_QUARTERS := 5
const COVER_TOTAL := 99

## Folga entre o centro de um token e uma parede ao andar (o token tem 0,65 m de raio).
const CLEARANCE := 0.3
const SQRT2 := 1.41421356

var w := 0
var h := 0
var cells := PackedByteArray()
var biome := ""


static func blank(width: int, height: int, fill := FLOOR) -> TerrainMap:
	var t := TerrainMap.new()
	t.w = width
	t.h = height
	t.cells.resize(width * height)
	t.cells.fill(fill)
	return t


static func from_rows(rows: Array, biome_id := "") -> TerrainMap:
	var t := TerrainMap.new()
	t.biome = biome_id
	if rows.is_empty():
		return t
	t.h = rows.size()
	t.w = str(rows[0]).length()
	t.cells.resize(t.w * t.h)
	t.cells.fill(FLOOR)
	for y in t.h:
		var row := str(rows[y])
		for x in mini(t.w, row.length()):
			t.cells[y * t.w + x] = row.unicode_at(x)
	return t


## Lê o mapa gravado na cena ({"rows": [...], "biome": ...}). Sem mapa, devolve o vazio.
static func from_scene(sc: Dictionary) -> TerrainMap:
	var m: Dictionary = sc.get("map", {})
	if m.is_empty():
		return TerrainMap.new()
	return from_rows(m.get("rows", []), str(m.get("biome", "")))


func to_rows() -> Array:
	var out: Array = []
	for y in h:
		var row := ""
		for x in w:
			row += char(cells[y * w + x])
		out.append(row)
	return out


func duplicate_map() -> TerrainMap:
	var t := TerrainMap.new()
	t.w = w
	t.h = h
	t.cells = cells.duplicate()
	t.biome = biome
	return t


func is_empty() -> bool:
	return w == 0 or h == 0


# ---------------------------------------------------------------- células

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func at(x: int, y: int) -> int:
	if is_empty():
		return FLOOR
	if not inside(x, y):
		return WALL
	return cells[y * w + x]


func set_at(x: int, y: int, c: int) -> void:
	if inside(x, y):
		cells[y * w + x] = c


func atv(c: Vector2i) -> int:
	return at(c.x, c.y)


static func cell_of(p_m: Vector2) -> Vector2i:
	return Vector2i(floori(p_m.x), floori(p_m.y))


static func center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


static func passable_code(c: int) -> bool:
	return c == FLOOR or c == ROUGH


static func sight_code(c: int) -> bool:
	return c == WALL or c == PILLAR


func passable(x: int, y: int) -> bool:
	return passable_code(at(x, y))


func passable_v(c: Vector2i) -> bool:
	return passable(c.x, c.y)


func rough(x: int, y: int) -> bool:
	return at(x, y) == ROUGH


func blocks_sight(x: int, y: int) -> bool:
	return sight_code(at(x, y))


func count(code: int) -> int:
	var n := 0
	for v in cells:
		if v == code:
			n += 1
	return n


## Um token pode ficar aqui? Célula livre e longe o bastante de tudo que não se atravessa.
func walkable_m(p: Vector2) -> bool:
	if is_empty():
		return true
	if not passable_v(cell_of(p)):
		return false
	for off in [Vector2(CLEARANCE, CLEARANCE), Vector2(-CLEARANCE, CLEARANCE), Vector2(CLEARANCE, -CLEARANCE), Vector2(-CLEARANCE, -CLEARANCE)]:
		if not passable_v(cell_of(p + off)):
			return false
	return true


## Ajusta um ponto escolhido no clique: se encosta demais numa parede, vai para o centro da célula.
func settle_m(p: Vector2) -> Vector2:
	if is_empty() or walkable_m(p):
		return p
	var c := cell_of(p)
	if passable_v(c):
		return center(c)
	return p


## Célula livre mais próxima (procura em anéis até max_r). Devolve Vector2i(-1, -1) se não achar.
func nearest_passable(p: Vector2, max_r := 8, mask := PackedByteArray()) -> Vector2i:
	var c0 := cell_of(p)
	if passable_v(c0) and (mask.is_empty() or (inside(c0.x, c0.y) and mask[c0.y * w + c0.x] != 0)):
		return c0
	var best := Vector2i(-1, -1)
	for r in range(1, max_r + 1):
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := c0 + Vector2i(dx, dy)
				if not passable_v(c):
					continue
				if not mask.is_empty() and mask[c.y * w + c.x] == 0:
					continue
				var d := center(c).distance_to(p)
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return best


# ---------------------------------------------------------------- linha de visão

## A reta de a até b atravessa alguma célula que tapa a visão? A célula de partida não conta.
## Percorre a grade célula por célula (Amanatides e Woo): exato e barato.
func ray_blocked(a: Vector2, b: Vector2) -> bool:
	if is_empty():
		return false
	var x := floori(a.x)
	var y := floori(a.y)
	var ex := floori(b.x)
	var ey := floori(b.y)
	var d := b - a
	var sx := 1 if d.x > 0.0 else (-1 if d.x < 0.0 else 0)
	var sy := 1 if d.y > 0.0 else (-1 if d.y < 0.0 else 0)
	var tmx := INF
	var tdx := INF
	if sx != 0:
		tmx = ((x + (1 if sx > 0 else 0)) - a.x) / d.x
		tdx = absf(1.0 / d.x)
	var tmy := INF
	var tdy := INF
	if sy != 0:
		tmy = ((y + (1 if sy > 0 else 0)) - a.y) / d.y
		tdy = absf(1.0 / d.y)
	var guard := w + h + 4
	while guard > 0:
		guard -= 1
		if x == ex and y == ey:
			return false
		if minf(tmx, tmy) > 1.0 + 1e-6:
			return false  # arredondamento: a reta termina nesta célula
		if absf(tmx - tmy) < 1e-6:
			# Passa exatamente pela quina: só bloqueia se as duas laterais tapam.
			if blocks_sight(x + sx, y) and blocks_sight(x, y + sy):
				return true
			tmx += tdx
			tmy += tdy
			x += sx
			y += sy
		elif tmx < tmy:
			tmx += tdx
			x += sx
		else:
			tmy += tdy
			y += sy
		if blocks_sight(x, y):
			return true
	return false


func line_clear(a: Vector2, b: Vector2) -> bool:
	return not ray_blocked(a, b)


## Cobertura do alvo em t vista de a (SRD 5.2.1: meia +2, três quartos +5, total não pode ser
## alvo direto). Traça retas de três pontos do atacante (ele pode se inclinar) até três pontos do
## alvo (centro e as bordas). Quantas retas uma parede corta decide o grau. Obstáculos baixos e
## criaturas no meio do caminho dão meia cobertura. Obstáculo colado no atacante não conta.
## others: posições (m) das outras criaturas, sem o atacante e o alvo.
func cover(a: Vector2, t: Vector2, others: Array = []) -> int:
	if is_empty():
		return COVER_NONE
	var dir := t - a
	if dir.length() < 0.05:
		return COVER_NONE
	var n := dir.normalized().orthogonal()
	var origins: Array = [a]
	for s in [0.45, -0.45]:
		var o: Vector2 = a + n * s
		if passable_v(cell_of(o)):
			origins.append(o)
	var targets: Array = [t]
	for s2 in [0.45, -0.45]:
		var tp: Vector2 = t + n * s2
		targets.append(tp if not sight_code(atv(cell_of(tp))) else t)
	var best := 3
	for o2 in origins:
		var blocked := 0
		for tp2 in targets:
			if ray_blocked(o2, tp2):
				blocked += 1
		best = mini(best, blocked)
	if best >= 3:
		return COVER_TOTAL
	if best == 2:
		return COVER_THREE_QUARTERS
	if best == 1:
		return COVER_HALF
	if _low_between(a, t):
		return COVER_HALF
	for op in others:
		var q: Vector2 = op
		var along := (q - a).dot(dir.normalized())
		if along < 0.8 or along > dir.length() - 0.8:
			continue
		if absf((q - a).cross(dir.normalized())) <= 0.55:
			return COVER_HALF
	return COVER_NONE


## Há um obstáculo baixo entre os dois, fora do alcance do braço do atacante?
func _low_between(a: Vector2, t: Vector2) -> bool:
	var length := a.distance_to(t)
	var steps := int(ceil(length / 0.2))
	var seen := {}
	for i in range(1, steps):
		var p := a.lerp(t, float(i) / float(steps))
		var c := cell_of(p)
		if seen.has(c):
			continue
		seen[c] = true
		if atv(c) == LOW and center(c).distance_to(a) > 1.2 and c != cell_of(t):
			return true
	return false


static func cover_name(c: int) -> String:
	match c:
		COVER_HALF:
			return "meia cobertura"
		COVER_THREE_QUARTERS:
			return "três quartos de cobertura"
		COVER_TOTAL:
			return "cobertura total"
	return ""


# ---------------------------------------------------------------- caminhos

func _step_cost(nx: int, ny: int, diag: bool) -> float:
	return (SQRT2 if diag else 1.0) * (2.0 if rough(nx, ny) else 1.0)


func _can_step(x: int, y: int, dx: int, dy: int, blocked: Dictionary) -> bool:
	var nx := x + dx
	var ny := y + dy
	if not passable(nx, ny) or blocked.has(Vector2i(nx, ny)):
		return false
	if dx != 0 and dy != 0:
		# Sem cortar quina: as duas laterais precisam estar livres.
		if not passable(x + dx, y) or not passable(x, y + dy):
			return false
	return true


const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## Distância andando (com terreno difícil custando o dobro) de `from` até cada célula, até max_cost.
## blocked: células proibidas (onde estão inimigos). Devolve {Vector2i: custo}.
func cost_field(from: Vector2, max_cost := INF, blocked := {}) -> Dictionary:
	var dist := {}
	if is_empty():
		return dist
	var s := cell_of(from)
	if not passable_v(s):
		s = nearest_passable(from, 3)
		if s.x < 0:
			return dist
	dist[s] = 0.0
	var heap := _Heap.new()
	heap.push(0.0, s)
	while not heap.empty():
		var top: Array = heap.pop()
		var dcur: float = top[0]
		var c: Vector2i = top[1]
		if dcur > float(dist.get(c, INF)) + 1e-6:
			continue
		for dv in DIRS:
			if not _can_step(c.x, c.y, dv.x, dv.y, blocked):
				continue
			var nc: Vector2i = c + dv
			var nd := dcur + _step_cost(nc.x, nc.y, dv.x != 0 and dv.y != 0)
			if nd > max_cost + 1e-6:
				continue
			if nd < float(dist.get(nc, INF)) - 1e-6:
				dist[nc] = nd
				heap.push(nd, nc)
	return dist


## Células alcançáveis a partir de uma célula (ignora custo). Máscara w*h com 1 = alcançável.
func reach_mask(from: Vector2i, blocked := {}) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	if not passable_v(from):
		return mask
	var stack: Array = [from]
	mask[from.y * w + from.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for dv in DIRS:
			if not _can_step(c.x, c.y, dv.x, dv.y, blocked):
				continue
			var nc: Vector2i = c + dv
			if mask[nc.y * w + nc.x] == 0:
				mask[nc.y * w + nc.x] = 1
				stack.append(nc)
	return mask


## Caminho andando de a até b (metros). Devolve {"points": PackedVector2Array, "cost": float}
## ou {} se não há caminho. O caminho é alisado: segue reto sempre que dá sem encostar em parede
## nem pagar mais terreno difícil do que o caminho em grade pagaria.
func find_path(a: Vector2, b: Vector2, blocked := {}) -> Dictionary:
	if is_empty():
		return {"points": PackedVector2Array([a, b]), "cost": a.distance_to(b)}
	var s := cell_of(a)
	if not passable_v(s):
		s = nearest_passable(a, 3)
		if s.x < 0:
			return {}
	var g := cell_of(b)
	if not passable_v(g) or blocked.has(g):
		return {}
	var came := {}
	var gs := {s: 0.0}
	var heap := _Heap.new()
	heap.push(_octile(s, g), s)
	var found := s == g
	while not heap.empty() and not found:
		var top: Array = heap.pop()
		var c: Vector2i = top[1]
		if c == g:
			found = true
			break
		var gc: float = gs[c]
		if float(top[0]) > gc + _octile(c, g) + 1e-6:
			continue
		for dv in DIRS:
			if not _can_step(c.x, c.y, dv.x, dv.y, blocked):
				continue
			var nc: Vector2i = c + dv
			var ng := gc + _step_cost(nc.x, nc.y, dv.x != 0 and dv.y != 0)
			if ng < float(gs.get(nc, INF)) - 1e-6:
				gs[nc] = ng
				came[nc] = c
				heap.push(ng + _octile(nc, g), nc)
	if not found:
		return {}
	var chain: Array = [g]
	while chain[0] != s:
		chain.push_front(came[chain[0]])
	var raw := PackedVector2Array([a])
	for i in range(1, chain.size() - 1):
		raw.append(center(chain[i]))
	raw.append(b)
	var smooth := _smooth(raw, blocked)
	return {"points": smooth, "cost": path_cost(smooth)}


static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + (SQRT2 - 1.0) * float(mini(dx, dy))


## Custo de andar pela linha (terreno difícil em dobro), medido em passos de 10 cm.
func path_cost(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += segment_cost(pts[i - 1], pts[i])
	return total


func segment_cost(p: Vector2, q: Vector2) -> float:
	var length := p.distance_to(q)
	if is_empty() or length < 1e-4:
		return length
	var steps := maxi(1, int(ceil(length / 0.1)))
	var step := length / float(steps)
	var total := 0.0
	for i in steps:
		var mid := p.lerp(q, (float(i) + 0.5) / float(steps))
		var c := cell_of(mid)
		total += step * (2.0 if rough(c.x, c.y) else 1.0)
	return total


## Dá para andar em linha reta de p até q? Sem atravessar nada e sem raspar em parede.
func walk_clear(p: Vector2, q: Vector2, blocked := {}) -> bool:
	if is_empty():
		return true
	var length := p.distance_to(q)
	var steps := maxi(1, int(ceil(length / 0.2)))
	for i in range(1, steps + 1):
		var s := p.lerp(q, float(i) / float(steps))
		var c := cell_of(s)
		if not passable_v(c) or blocked.has(c):
			return false
		for off in [Vector2(CLEARANCE, CLEARANCE), Vector2(-CLEARANCE, CLEARANCE), Vector2(CLEARANCE, -CLEARANCE), Vector2(-CLEARANCE, -CLEARANCE)]:
			var oc := cell_of(s + off)
			if not passable_v(oc):
				return false
	return true


func _smooth(raw: PackedVector2Array, blocked: Dictionary) -> PackedVector2Array:
	if raw.size() <= 2:
		return raw
	var cum := PackedFloat32Array([0.0])
	for i in range(1, raw.size()):
		cum.append(cum[i - 1] + segment_cost(raw[i - 1], raw[i]))
	var out := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1:
			if walk_clear(raw[i], raw[j], blocked) and segment_cost(raw[i], raw[j]) <= cum[j] - cum[i] + 0.01:
				break
			j -= 1
		out.append(raw[j])
		i = j
	return out


## Corta o caminho no ponto em que o custo acumulado chega a `budget`.
func truncate(pts: PackedVector2Array, budget: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	var left := budget
	for i in range(1, pts.size()):
		var c := segment_cost(pts[i - 1], pts[i])
		if c <= left + 1e-4:
			out.append(pts[i])
			left -= c
			continue
		# Anda o quanto dá neste trecho, em passos de 10 cm.
		var length := pts[i - 1].distance_to(pts[i])
		var steps := maxi(1, int(ceil(length / 0.1)))
		var last := pts[i - 1]
		for k in range(1, steps + 1):
			var s := pts[i - 1].lerp(pts[i], float(k) / float(steps))
			var sc := segment_cost(last, s)
			if sc > left + 1e-4:
				break
			left -= sc
			last = s
		if last != pts[i - 1]:
			out.append(last)
		break
	return out


## Pontos ao longo do caminho, a cada `step` metros (para revelar e disparar emboscadas no trajeto).
static func samples(pts: PackedVector2Array, step := 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		var length := pts[i - 1].distance_to(pts[i])
		var n := maxi(1, int(ceil(length / step)))
		for k in range(1, n + 1):
			out.append(pts[i - 1].lerp(pts[i], float(k) / float(n)))
	return out


static func length_of(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


# ---------------------------------------------------------------- visão em área

## Células vistas de p até `radius` metros (centro da célula com linha de visão).
func visible_from(p: Vector2, radius: float) -> Array:
	var out: Array = []
	if is_empty():
		return out
	var c0 := cell_of(p)
	var r := int(ceil(radius))
	for y in range(maxi(0, c0.y - r), mini(h, c0.y + r + 1)):
		for x in range(maxi(0, c0.x - r), mini(w, c0.x + r + 1)):
			var cc := center(Vector2i(x, y))
			if cc.distance_to(p) > radius:
				continue
			if Vector2i(x, y) == c0 or not ray_blocked(p, cc) or _edge_visible(p, x, y):
				out.append(Vector2i(x, y))
	return out


## Uma parede é vista se alguma das quinas dela é vista: sem isso as paredes ficam no escuro.
func _edge_visible(p: Vector2, x: int, y: int) -> bool:
	if not blocks_sight(x, y):
		return false
	for off in [Vector2(0.05, 0.05), Vector2(0.95, 0.05), Vector2(0.05, 0.95), Vector2(0.95, 0.95), Vector2(0.5, 0.02), Vector2(0.5, 0.98), Vector2(0.02, 0.5), Vector2(0.98, 0.5)]:
		var q: Vector2 = Vector2(x, y) + off
		if q.distance_to(p) < 0.01:
			continue
		# A reta até a borda não pode passar por outra célula que tapa a visão.
		var mid: Vector2 = q - (q - p).normalized() * 0.08
		if cell_of(mid) == Vector2i(x, y):
			continue
		if not ray_blocked(p, mid):
			return true
	return false


# ---------------------------------------------------------------- fila de prioridade

class _Heap:
	var keys: Array = []
	var vals: Array = []

	func empty() -> bool:
		return keys.is_empty()

	func push(k: float, v: Variant) -> void:
		keys.append(k)
		vals.append(v)
		var i := keys.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> Array:
		var out := [keys[0], vals[0]]
		var last := keys.size() - 1
		_swap(0, last)
		keys.pop_back()
		vals.pop_back()
		var i := 0
		var n := keys.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < n and keys[l] < keys[m]:
				m = l
			if r < n and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return out

	func _swap(a: int, b: int) -> void:
		var tk = keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv = vals[a]
		vals[a] = vals[b]
		vals[b] = tv
