/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "connection.h"

#include <framework/core/application.h>
#include <framework/core/eventdispatcher.h>
#include <boost/asio.hpp>
#include <framework/util/stats.h>
#include <framework/util/extras.h>
#include <chrono>
#include <cstdlib>

asio::io_service g_ioService;
std::list<std::shared_ptr<asio::streambuf>> Connection::m_outputStreams;

Connection::Connection() :
        m_readTimer(g_ioService),
        m_writeTimer(g_ioService),
        m_delayedWriteTimer(g_ioService),
        m_resolver(g_ioService),
        m_socket(g_ioService)
{
    m_connected = false;
    m_connecting = false;
}

Connection::~Connection()
{
    VALIDATE(!g_app.isTerminated());
    close();
}

void Connection::poll()
{
    AutoStat s(STATS_MAIN, "PollConnection");
    // reset must always be called prior to poll
    g_ioService.reset();
    g_ioService.poll();
}

void Connection::terminate()
{
    g_ioService.stop();
    m_outputStreams.clear();
}

void Connection::close()
{
    if(!m_connected && !m_connecting)
        return;

    // flush send data before disconnecting on clean connections
    if(m_connected && !m_error && m_outputStream)
        internal_write();

    m_connecting = false;
    m_connected = false;
    m_connectCallback = nullptr;
    m_errorCallback = nullptr;
    m_recvCallback = nullptr;

    m_resolver.cancel();
    m_readTimer.cancel();
    m_writeTimer.cancel();
    m_delayedWriteTimer.cancel();

    if(m_socket.is_open()) {
        boost::system::error_code ec;
        m_socket.shutdown(boost::asio::ip::tcp::socket::shutdown_both, ec);
        m_socket.close();
    }
}

void Connection::connect(const std::string& host, uint16 port, const std::function<void()>& connectCallback)
{
    m_connected = false;
    m_connecting = true;
    m_error.clear();
    m_connectCallback = connectCallback;

    auto env = [](const char* name) { const char* value = std::getenv(name); return value ? std::string(value) : std::string(); };
    m_socksHost = g_app.isHeadless() ? env("OTC_SOCKS_HOST") : "";
    m_socksUser = env("OTC_SOCKS_USER");
    m_socksPassword = env("OTC_SOCKS_PASSWORD");
    m_destinationHost = host;
    m_destinationPort = port;
    const std::string proxyPort = env("OTC_SOCKS_PORT");
    if (!m_socksHost.empty() && (proxyPort.empty() || m_socksUser.size() > 255 || m_socksPassword.size() > 255 || host.empty() || host.size() > 255)) {
        handleError(asio::error::invalid_argument);
        return;
    }
    asio::ip::tcp::resolver::query query(m_socksHost.empty() ? host : m_socksHost, m_socksHost.empty() ? stdext::unsafe_cast<std::string>(port) : proxyPort);
    m_resolver.async_resolve(query, std::bind(&Connection::onResolve, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::internal_connect(asio::ip::basic_resolver<asio::ip::tcp>::iterator endpointIterator)
{
    m_socket.async_connect(*endpointIterator, std::bind(&Connection::onConnect, asConnection(), std::placeholders::_1));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::write(uint8* buffer, size_t size)
{
    if(!m_connected)
        return;

    // we can't send the data right away, otherwise we could create tcp congestion
    if(!m_outputStream) {
        if(!m_outputStreams.empty()) {
            m_outputStream = m_outputStreams.front();
            m_outputStreams.pop_front();
        } else
            m_outputStream = std::shared_ptr<asio::streambuf>(new asio::streambuf);

        m_delayedWriteTimer.cancel();
        m_delayedWriteTimer.expires_from_now(std::chrono::milliseconds(0));
        m_delayedWriteTimer.async_wait(std::bind(&Connection::onCanWrite, asConnection(), std::placeholders::_1));
    }

    std::ostream os(m_outputStream.get());
    os.write((const char*)buffer, size);
    os.flush();
}

void Connection::internal_write()
{
    if(!m_connected)
        return;

    std::shared_ptr<asio::streambuf> outputStream = m_outputStream;
    m_outputStream = nullptr;

    asio::async_write(m_socket,
                      *outputStream,
                      std::bind(&Connection::onWrite, asConnection(), std::placeholders::_1, std::placeholders::_2, outputStream));

    m_writeTimer.cancel();
    m_writeTimer.expires_from_now(std::chrono::seconds(WRITE_TIMEOUT));
    m_writeTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read(uint32 bytes, const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    asio::async_read(m_socket,
                     asio::buffer(m_inputStream.prepare(bytes)),
                     std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read_until(const std::string& what, const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    asio::async_read_until(m_socket,
                           m_inputStream,
                           what.c_str(),
                           std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read_some(const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    m_socket.async_read_some(asio::buffer(m_inputStream.prepare(RECV_BUFFER_SIZE)),
                             std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::onResolve(const boost::system::error_code& error, asio::ip::basic_resolver<asio::ip::tcp>::iterator endpointIterator)
{
    m_readTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    if(!error)
        internal_connect(endpointIterator);
    else
        handleError(error);
}

void Connection::onConnect(const boost::system::error_code& error)
{
    m_readTimer.cancel();
    if(error == asio::error::operation_aborted) return;
    if(error) { handleError(error); return; }
    if(!m_socksHost.empty()) {
        m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
        m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
        socksHandshake();
        return;
    }
    finishConnect();
}

void Connection::finishConnect()
{
    m_readTimer.cancel();
    m_activityTimer.restart();
    m_connected = true;
    m_connecting = false;
    boost::system::error_code ec;
    m_socket.set_option(boost::asio::ip::tcp::no_delay(true), ec);
    m_socket.set_option(boost::asio::socket_base::send_buffer_size(g_app.isHeadless() ? 32768 : 524288), ec);
    m_socket.set_option(boost::asio::socket_base::receive_buffer_size(g_app.isHeadless() ? 32768 : 524288), ec);
    if(m_connectCallback) m_connectCallback();
}

void Connection::socksHandshake()
{
    using Bytes = std::vector<uint8>;
    using Next = std::function<void(const Bytes&)>;
    auto self = asConnection();
    auto fail = [self](const boost::system::error_code& ec) {
        if(self->m_connecting) self->handleError(ec);
    };
    auto read = [self, fail](size_t size, Next next) {
        auto data = std::make_shared<Bytes>(size);
        asio::async_read(self->m_socket, asio::buffer(*data), [self, fail, data, next](const boost::system::error_code& ec, size_t) {
            if(!self->m_connecting) return;
            if(ec) { fail(ec); return; }
            next(*data);
        });
    };
    auto exchange = [self, fail, read](Bytes request, size_t size, Next next) {
        auto data = std::make_shared<Bytes>(std::move(request));
        asio::async_write(self->m_socket, asio::buffer(*data), [self, fail, read, data, size, next](const boost::system::error_code& ec, size_t) {
            if(!self->m_connecting) return;
            if(ec) { fail(ec); return; }
            read(size, next);
        });
    };
    auto rejected = [fail]() { fail(asio::error::access_denied); };
    auto request = [self, read, exchange, rejected]() {
        Bytes msg{5,1,0,3,static_cast<uint8>(self->m_destinationHost.size())};
        msg.insert(msg.end(),self->m_destinationHost.begin(),self->m_destinationHost.end());
        msg.push_back(static_cast<uint8>(self->m_destinationPort >> 8));
        msg.push_back(static_cast<uint8>(self->m_destinationPort & 255));
        exchange(std::move(msg),4,[self,read,rejected](const Bytes& reply) {
            if(reply[0]!=5 || reply[1]!=0 || reply[2]!=0) { rejected(); return; }
            auto done = [self](const Bytes&) { self->finishConnect(); };
            if(reply[3]==1) read(6,done);
            else if(reply[3]==4) read(18,done);
            else if(reply[3]==3) read(1,[read,done](const Bytes& length) { read(static_cast<size_t>(length[0])+2,done); });
            else rejected();
        });
    };
    bool auth = !m_socksUser.empty();
    exchange(Bytes{5,1,static_cast<uint8>(auth ? 2 : 0)},2,[self,exchange,request,rejected,auth](const Bytes& reply) {
        if(reply[0]!=5 || reply[1]!=(auth?2:0)) { rejected(); return; }
        if(!auth) { request(); return; }
        Bytes msg{1,static_cast<uint8>(self->m_socksUser.size())};
        msg.insert(msg.end(),self->m_socksUser.begin(),self->m_socksUser.end());
        msg.push_back(static_cast<uint8>(self->m_socksPassword.size()));
        msg.insert(msg.end(),self->m_socksPassword.begin(),self->m_socksPassword.end());
        self->m_socksPassword.clear();
        exchange(std::move(msg),2,[request,rejected](const Bytes& result) {
            if(result[0]!=1 || result[1]!=0) { rejected(); return; }
            request();
        });
    });
}

void Connection::onCanWrite(const boost::system::error_code& error)
{
    m_delayedWriteTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    if(m_connected)
        internal_write();
}

void Connection::onWrite(const boost::system::error_code& error, size_t writeSize, std::shared_ptr<asio::streambuf> outputStream)
{
    m_writeTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    // free output stream and store for using it again later
    outputStream->consume(outputStream->size());
    m_outputStreams.push_back(outputStream);

    if(m_connected && error)
        handleError(error);
}

void Connection::onRecv(const boost::system::error_code& error, size_t recvSize)
{
    m_readTimer.cancel();
    m_activityTimer.restart();

    if(error == asio::error::operation_aborted)
        return;

    if(m_connected) {
        if(!error) {
            if(m_recvCallback) {
                const char* header = boost::asio::buffer_cast<const char*>(m_inputStream.data());
                m_recvCallback((uint8*)header, recvSize);
            }
        } else
            handleError(error);
    }

    if(!error)
        m_inputStream.consume(recvSize);
}

void Connection::onTimeout(const boost::system::error_code& error)
{
    if(error == asio::error::operation_aborted)
        return;

    handleError(asio::error::timed_out);
}

void Connection::handleError(const boost::system::error_code& error)
{
    if(error == asio::error::operation_aborted)
        return;

    m_error = error;
    if(m_errorCallback)
        m_errorCallback(error);
    if(m_connected || m_connecting)
        close();
}

int Connection::getIp()
{
    boost::system::error_code error;
    const boost::asio::ip::tcp::endpoint ip = m_socket.remote_endpoint(error);
    if(!error)
        return boost::asio::detail::socket_ops::host_to_network_long(ip.address().to_v4().to_ulong());

    g_logger.error("Getting remote ip");
    return 0;
}
