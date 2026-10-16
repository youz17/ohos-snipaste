import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PinStore';

export class PinStore {
  /**
   * 把 PixelMap 以 PNG 落盘到应用沙箱，返回绝对路径。
   * 贴图窗口是独立 Ability（可能与本页不同进程），用文件传递比内存对象可靠。
   */
  static async saveAsPng(pixelMap: image.PixelMap, filesDir: string, prefix: string = 'pin'): Promise<string> {
    const filePath: string = `${filesDir}/${prefix}_${Date.now()}.png`;
    const packer = image.createImagePacker();
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      hilog.info(DOMAIN, TAG, 'saved: %{public}s', filePath);
      return filePath;
    } finally {
      packer.release();
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  /**
   * 从沙箱文件解码出 PixelMap。
   * 用 fd 打开而不是把路径交给图片组件，避免路径/URI 解析差异导致图片不显示。
   */
  static async decode(path: string): Promise<image.PixelMap> {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const source: image.ImageSource = image.createImageSource(file.fd);
      try {
        // 固定要 RGBA_8888：图片比较要按 4 字节/像素直接读像素缓冲
        const pixelMap: image.PixelMap = await source.createPixelMap({
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        const info: image.ImageInfo = await pixelMap.getImageInfo();
        hilog.info(DOMAIN, TAG, 'decoded %{public}s: %{public}dx%{public}d',
          path, info.size.width, info.size.height);
        return pixelMap;
      } finally {
        source.release();
      }
    } finally {
      fs.closeSync(file);
    }
  }
}
