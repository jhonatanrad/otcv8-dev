"""Offline SOCKS5 handshake tests. No connection to any game server."""
import os, pathlib, socket, subprocess, threading
root = pathlib.Path(__file__).resolve().parent.parent
def exact(s,n):
    b=b''
    while len(b)<n:
        part=s.recv(n-len(b))
        if not part: raise RuntimeError("premature close")
        b+=part
    return b
for auth in (False,True):
    log=root/'otclient-headless.log'
    log.unlink(missing_ok=True)
    errors=[]
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0)); listener.listen(1); listener.settimeout(12)
        def server():
            try:
                s,_=listener.accept()
                with s:
                    s.settimeout(10)
                    assert exact(s,3)==bytes([5,1,2 if auth else 0])
                    s.sendall(bytes([5,2 if auth else 0]))
                    if auth:
                        assert exact(s,2)==b'\x01\x04'
                        assert exact(s,4)==b'test'
                        assert exact(s,1)==b'\x04'
                        assert exact(s,4)==b'pass'
                        s.sendall(b'\x01\x00')
                    assert exact(s,4)==b'\x05\x01\x00\x03'
                    n=exact(s,1)[0]
                    assert exact(s,n)==b'example.invalid'
                    assert int.from_bytes(exact(s,2),'big')==7172
                    s.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
            except Exception as e:
                errors.append(repr(e))
        t=threading.Thread(target=server,daemon=True);t.start()
        env=os.environ.copy()
        env.update(OTC_HEADLESS_PROXY_TEST='1',OTC_SOCKS_HOST='127.0.0.1',OTC_SOCKS_PORT=str(listener.getsockname()[1]),OTC_SOCKS_USER='test' if auth else '',OTC_SOCKS_PASSWORD='pass' if auth else '')
        p=subprocess.run([str(root/'otclient_headless.exe'),'--headless-smoke'],cwd=root,env=env,timeout=15)
        t.join(12)
        assert not t.is_alive() and not errors, errors
        assert p.returncode==0 and 'SOCKS_SMOKE_OK' in log.read_text(errors='replace')
        print('SOCKS5 offline handshake passed, authentication:',auth)
