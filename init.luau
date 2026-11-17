--!native
--!strict
--!optimize 2

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Resolution (STAR_SIZE and ANGLE_STEPS must be powers of two)
local FRAME_SIZE = 512
local STAR_SIZE = 512
local ANGLE_STEPS = 1024
local RING_COUNT = 128

-- Geometry, as fractions of half the frame
local HORIZON_RADIUS = 0.12
local DISK_RADIUS = 0.42
local EINSTEIN_RADIUS = 0.5

-- Motion
local STAR_COUNT = 1500
local STAR_DRIFT = 24 -- texels per second
local INNER_ORBITS_PER_SECOND = 0.5

-- Byte layout: every texel is one little-endian u32 (RGBA)
local TEXEL = 4
local OPAQUE_BLACK = 0xFF000000

local FRAME_BYTES = FRAME_SIZE * FRAME_SIZE * TEXEL
local STAR_COLUMN_BYTES = STAR_SIZE * TEXEL
local STAR_BYTES = STAR_SIZE * STAR_COLUMN_BYTES
local RING_BYTES = ANGLE_STEPS * TEXEL
local DISK_BYTES = RING_COUNT * RING_BYTES

-- Scene buffer: [void texel][drifted stars][orbited disk]
local VOID_OFFSET = 0
local STAR_OFFSET = VOID_OFFSET + TEXEL
local DISK_OFFSET = STAR_OFFSET + STAR_BYTES
local SCENE_BYTES = DISK_OFFSET + DISK_BYTES

local LATTICE_SIZE = 64

local function packColor(red: number, green: number, blue: number): number
	return OPAQUE_BLACK + (blue * 255 // 1) * 0x10000 + (green * 255 // 1) * 0x100 + red * 255 // 1
end

local function createLattice(random: Random): buffer
	local lattice = buffer.create(LATTICE_SIZE * LATTICE_SIZE)
	for offset = 0, buffer.len(lattice) - 1 do
		buffer.writeu8(lattice, offset, random:NextInteger(0, 255))
	end
	return lattice
end

-- Smoothstepped value noise; u wraps at `period` so the disk closes seamlessly
local function sampleLattice(lattice: buffer, u: number, v: number, period: number): number
	local cellU, cellV = u // 1, v // 1
	local fadeU, fadeV = u - cellU, v - cellV
	fadeU *= fadeU * (3 - 2 * fadeU)
	fadeV *= fadeV * (3 - 2 * fadeV)

	local left, right = cellU % period, (cellU + 1) % period
	local top = cellV % LATTICE_SIZE * LATTICE_SIZE
	local bottom = (cellV + 1) % LATTICE_SIZE * LATTICE_SIZE

	return math.lerp(
		math.lerp(buffer.readu8(lattice, top + left), buffer.readu8(lattice, top + right), fadeU),
		math.lerp(buffer.readu8(lattice, bottom + left), buffer.readu8(lattice, bottom + right), fadeU),
		fadeV
	) / 255
end

-- Stored column-major, so a flat byte shift is an exact horizontal drift
local function createStarTexture(random: Random): buffer
	local stars = buffer.create(STAR_BYTES)
	for offset = 0, STAR_BYTES - TEXEL, TEXEL do
		buffer.writeu32(stars, offset, OPAQUE_BLACK)
	end

	for _ = 1, STAR_COUNT do
		local brightness = 0.2 + 0.8 * random:NextNumber() ^ 3
		local warmth = random:NextNumber()
		local color = packColor(
			brightness * math.lerp(0.7, 1, warmth),
			brightness * 0.85,
			brightness * math.lerp(1, 0.7, warmth)
		)
		buffer.writeu32(stars, random:NextInteger(0, STAR_SIZE * STAR_SIZE - 1) * TEXEL, color)
	end
	return stars
end

-- Polar texture: one row per ring, one texel per angle step
local function createDiskTexture(random: Random): buffer
	local lattice = createLattice(random)
	local disk = buffer.create(DISK_BYTES)

	for ring = 0, RING_COUNT - 1 do
		local depth = ring / (RING_COUNT - 1)
		local glow = (1 - depth) ^ 1.5
		local photonRing = math.max(0, 1 - depth * 20)

		for step = 0, ANGLE_STEPS - 1 do
			local turn = step / ANGLE_STEPS
			local streaks = 0.5 * sampleLattice(lattice, turn * 8, depth * 12, 8)
				+ 0.3 * sampleLattice(lattice, turn * 16, depth * 24 + 17, 16)
				+ 0.2 * sampleLattice(lattice, turn * 32, depth * 48 + 41, 32)

			-- Black-body ramp: black, red, yellow, white
			local heat = 3 * (glow * (0.25 + 1.5 * streaks) + photonRing)
			local color = packColor(math.clamp(heat, 0, 1), math.clamp(heat - 1, 0, 1), math.clamp(heat - 2, 0, 1))
			buffer.writeu32(disk, (ring * ANGLE_STEPS + step) * TEXEL, color)
		end
	end
	return disk
end

-- For every frame pixel, the scene byte offset it will show
local function createGatherMap(): buffer
	local gatherMap = buffer.create(FRAME_BYTES)

	local half = FRAME_SIZE / 2
	local horizonSq = (HORIZON_RADIUS * half) ^ 2
	local diskSq = (DISK_RADIUS * half) ^ 2
	local einsteinSq = (EINSTEIN_RADIUS * half) ^ 2
	local diskInner = HORIZON_RADIUS * half
	local ringsPerPixel = RING_COUNT / ((DISK_RADIUS - HORIZON_RADIUS) * half)
	local stepsPerRadian = ANGLE_STEPS / (2 * math.pi)

	for y = 0, FRAME_SIZE - 1 do
		local dy = y + 0.5 - half
		for x = 0, FRAME_SIZE - 1 do
			local dx = x + 0.5 - half
			local distanceSq = dx * dx + dy * dy
			local sceneOffset = VOID_OFFSET

			if distanceSq >= diskSq then
				-- Point-mass lens, beta = theta * (1 - thetaE^2 / theta^2): no sqrt, no trig
				local lens = 1 - einsteinSq / distanceSq
				local column = (dx * lens) // 1 % STAR_SIZE
				local row = (dy * lens) // 1 % STAR_SIZE
				sceneOffset = STAR_OFFSET + (column * STAR_SIZE + row) * TEXEL
			elseif distanceSq >= horizonSq then
				local ring = math.min(((math.sqrt(distanceSq) - diskInner) * ringsPerPixel) // 1, RING_COUNT - 1)
				local step = (math.atan2(dy, dx) * stepsPerRadian) // 1 % ANGLE_STEPS
				sceneOffset = DISK_OFFSET + (ring * ANGLE_STEPS + step) * TEXEL
			end

			buffer.writeu32(gatherMap, (y * FRAME_SIZE + x) * TEXEL, sceneOffset)
		end
	end
	return gatherMap
end

-- Keplerian shear: angular speed falls off as radius^-1.5
local function createRingSpeeds(): { number }
	local ringSpeeds = table.create(RING_COUNT)
	for ring = 0, RING_COUNT - 1 do
		local radius = HORIZON_RADIUS + (DISK_RADIUS - HORIZON_RADIUS) * ring / RING_COUNT
		ringSpeeds[ring + 1] = INNER_ORBITS_PER_SECOND * ANGLE_STEPS * (HORIZON_RADIUS / radius) ^ 1.5
	end
	return ringSpeeds
end

-- Circular shift of the whole starfield in two block copies
local function driftStars(scene: buffer, stars: buffer, elapsed: number)
	local head = (elapsed * STAR_DRIFT) // 1 % STAR_SIZE * STAR_COLUMN_BYTES
	local tail = STAR_BYTES - head
	buffer.copy(scene, STAR_OFFSET, stars, head, tail)
	buffer.copy(scene, STAR_OFFSET + tail, stars, 0, head)
end

-- Circular shift of each ring by its own orbital phase
local function orbitDisk(scene: buffer, disk: buffer, ringSpeeds: { number }, elapsed: number)
	for ring = 0, RING_COUNT - 1 do
		local ringStart = ring * RING_BYTES
		local head = (elapsed * ringSpeeds[ring + 1]) // 1 % ANGLE_STEPS * TEXEL
		local tail = RING_BYTES - head
		buffer.copy(scene, DISK_OFFSET + ringStart, disk, ringStart + head, tail)
		buffer.copy(scene, DISK_OFFSET + ringStart + tail, disk, ringStart, head)
	end
end

-- The only per-pixel work: two reads and one write, whole texels at a time
local function gather(frame: buffer, scene: buffer, gatherMap: buffer)
	for offset = 0, FRAME_BYTES - TEXEL, TEXEL do
		buffer.writeu32(frame, offset, buffer.readu32(scene, buffer.readu32(gatherMap, offset)))
	end
end

local random = Random.new(1915)
local stars = createStarTexture(random)
local disk = createDiskTexture(random)
local gatherMap = createGatherMap()
local ringSpeeds = createRingSpeeds()

local scene = buffer.create(SCENE_BYTES)
buffer.writeu32(scene, VOID_OFFSET, OPAQUE_BLACK)

local frame = buffer.create(FRAME_BYTES)
local frameSize = Vector2.new(FRAME_SIZE, FRAME_SIZE)
local image = AssetService:CreateEditableImage({ Size = frameSize })

local screen = Instance.new("ScreenGui")
screen.Name = "BlackHole"
screen.ResetOnSpawn = false

local label = Instance.new("ImageLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromOffset(FRAME_SIZE, FRAME_SIZE)
label.BackgroundColor3 = Color3.new()
label.BorderSizePixel = 0
label.ImageContent = Content.fromObject(image)
label.Parent = screen

screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local startTime = os.clock()

RunService.PreRender:Connect(function()
	local elapsed = os.clock() - startTime
	driftStars(scene, stars, elapsed)
	orbitDisk(scene, disk, ringSpeeds, elapsed)
	gather(frame, scene, gatherMap)
	image:WritePixelsBuffer(Vector2.zero, frameSize, frame)
end)
