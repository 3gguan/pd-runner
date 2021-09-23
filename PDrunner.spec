# -*- mode: python -*-

block_cipher = None


a = Analysis(['PDrunner.py'],
             pathex=[''],
             binaries=[],
             datas=[('res','res')],
             hiddenimports=[],
             hookspath=[],
             runtime_hooks=[],
             excludes=[],
             win_no_prefer_redirects=False,
             win_private_assemblies=False,
             cipher=block_cipher,
             noarchive=False)
pyz = PYZ(a.pure, a.zipped_data,
             cipher=block_cipher)
exe = EXE(pyz,
          a.scripts,
          a.binaries,
          a.zipfiles,
          a.datas,
          [],
          name='PDrunner',
          debug=False,
          bootloader_ignore_signals=False,
          strip=False,
          upx=True,
          runtime_tmpdir=None,
          console=True )
app = BUNDLE(exe,
          name='PDrunner.app',
          icon='./res/icon.icns',
          bundle_identifier='lihaoyun6.PDrunner',
          info_plist={
           'NSHighResolutionCapable': True,
           'LSUIElement': True,
           'CFBundleShortVersionString': '0.1.0',
           'NSHumanReadableCopyright': u'Copyright (C) 2021 lihaoyun6. All rights reserved.'
           })