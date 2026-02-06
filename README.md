# SSTV.jl

Julia语言实现的SSTV（慢扫描电视）编码器。

## 功能特性

- 支持多种SSTV模式：
  - **灰度模式**: Robot8BW, Robot24BW
  - **彩色模式**: Robot36, Martin M1/M2, Scottie S1/S2
- 生成标准WAV格式的SSTV音频文件
- 可配置采样率和位深度
- 支持VOX音调和FSKID文本

## 安装

```julia
using Pkg
Pkg.add(url="https://github.com/yourusername/sstv.jl")
```

或者本地开发：

```julia
using Pkg
Pkg.develop(path="path/to/sstv.jl")
```

也可以：
```julia
]pkg
activate .
```

## 使用方法

### 基本用法

```julia
using SSTV
using Images

# 加载或创建图像
img = load("your_image.png")

# 创建SSTV编码器（Robot36模式）
sstv = Robot36(img, 11025, 16)  # 采样率11025Hz, 16位

# 生成WAV文件
write_wav(sstv, "output.wav")
```

### 支持的模式

#### 灰度模式
- `Robot8BW`: 160x120, 60秒
- `Robot24BW`: 320x240, 93秒

#### 彩色模式
- `Robot36`: 320x240, YCbCr编码
- `MartinM1`: 320x256, 114秒, RGB顺序: GBR
- `MartinM2`: 160x256, 58秒, RGB顺序: GBR
- `ScottieS1`: 320x256, 110秒, RGB顺序: RGB
- `ScottieS2`: 160x256, 71秒, RGB顺序: RGB

### 高级功能

#### 启用VOX音调
```julia
sstv = Robot36(img)
enable_vox!(sstv)
write_wav(sstv, "output_with_vox.wav")
```

#### 添加FSKID文本
```julia
sstv = Robot36(img)
add_fskid_text!(sstv, "CALLSIGN") # CALLSIGN为你的呼号，比如BA4HAM
write_wav(sstv, "output_with_fskid.wav")
```

#### 自定义采样率和位深度
```julia
# 22050Hz采样率, 16位
sstv = Robot36(img, 22050, 16)

# 11025Hz采样率, 8位
sstv = Robot36(img, 11025, 8)
```

## 示例

查看 `examples/example.jl` 获取更多示例代码。

运行示例：
```julia
include("examples/example.jl")
```

## 许可证

MIT License

## 参考

- [SSTV Wikipedia](https://en.wikipedia.org/wiki/Slow-scan_television)
- [Classic SSTV](https://www.classicsstv.com/)

## 贡献

欢迎提交Issue和Pull Request！
