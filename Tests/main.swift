// Run with swiftc SkyboxProbe/FrameSampler.swift Tests/main.swift -o /tmp/skybox-sampler-tests
var sampler = FrameSampler(interval: 20)
assert(!sampler.isDue(.nan))
assert(!sampler.isDue(.infinity))
assert(sampler.isDue(100))
sampler.didSave(100)
assert(!sampler.isDue(119.999))
assert(sampler.isDue(120))
assert(sampler.isDue(121))
assert(sampler.isDue(0)) // Stream timestamp reset.
sampler.didSave(120)
assert(!sampler.isDue(120))
sampler.reset()
assert(sampler.isDue(121)) // Restart need not wait for the prior interval.
print("FrameSampler checks passed")
