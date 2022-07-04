// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.16 <0.9.0;

contract Verifier {
    uint32 constant m_sep = 3 << 7;
    uint32 constant c_sep = 2 << 7;

    function convert_scalar(
        uint256[] memory m,
        uint256[] memory proof,
        uint256 v
    ) internal pure returns (uint256) {
        if (v >= m_sep) {
            return m[v - m_sep];
        } else if (v >= c_sep) {
            return v - c_sep;
        } else {
            return proof[v];
        }
    }

    function convert_point(
        uint256[] memory m,
        uint256[] memory proof,
        uint256 v
    ) internal pure returns (uint256, uint256) {
        if (v >= m_sep) {
            return (m[v - m_sep], m[v - m_sep + 1]);
        } else if (v >= c_sep) {
            revert();
        } else {
            return (proof[v], proof[v + 1]);
        }
    }

    function update(
        uint256[] memory m,
        uint256[] memory proof,
        uint256[] memory absorbing,
        uint256 opcodes
    ) internal view {
        uint32 i;
        uint256[4] memory buf;
        for (i = 0; i < 8; i++) {
            uint32 opcode = uint32(
                (opcodes >> ((7 - i) * 32)) & ((1 << 32) - 1)
            );
            if (opcode != 0) {
                uint32 t = (opcode >> 31);
                uint32 l =  (opcode >> 22) & 0x1ff;
                uint32 op = (opcode >> 18) & 0xf;
                uint32 r0 = (opcode >> 9) & 0x1ff;
                uint32 r1 = opcode & 0x1ff;

                l = l - m_sep;
                buf[0] = convert_scalar(m, proof, r0);
                buf[1] = convert_scalar(m, proof, r1);
                if (op == 1) {
                    m[l] = fr_add(buf[0], buf[1]);
                } else if (op == 3) {
                    m[l] = fr_mul(buf[0], buf[1]);
                } else if (op == 2) {
                    m[l] = fr_sub(buf[0], buf[1]);
                } else if (op == 4) {
                    m[l] = fr_div(buf[0], buf[1]);
                } else {
                    revert();
                }
            }
        }
    }

    function pairing(G1Point[] memory p1, G2Point[] memory p2)
        internal
        view
        returns (bool)
    {
        uint256 length = p1.length * 6;
        uint256[] memory input = new uint256[](length);
        uint256[1] memory result;
        bool ret;

        require(p1.length == p2.length);

        for (uint256 i = 0; i < p1.length; i++) {
            input[0 + i * 6] = p1[i].x;
            input[1 + i * 6] = p1[i].y;
            input[2 + i * 6] = p2[i].x[0];
            input[3 + i * 6] = p2[i].x[1];
            input[4 + i * 6] = p2[i].y[0];
            input[5 + i * 6] = p2[i].y[1];
        }

        assembly {
            ret := staticcall(
                gas(),
                8,
                add(input, 0x20),
                mul(length, 0x20),
                result,
                0x20
            )
        }
        require(ret);
        return result[0] != 0;
    }

    uint256 constant q_mod =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function fr_add(uint256 a, uint256 b) internal pure returns (uint256 r) {
        return addmod(a, b, q_mod);
    }

    function fr_sub(uint256 a, uint256 b) internal pure returns (uint256 r) {
        return addmod(a, q_mod - b, q_mod);
    }

    function fr_mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulmod(a, b, q_mod);
    }

    function fr_invert(uint256 a) internal view returns (uint256) {
        return fr_pow(a, q_mod - 2);
    }

    function fr_pow(uint256 a, uint256 power) internal view returns (uint256) {
        uint256[6] memory input;
        uint256[1] memory result;
        bool ret;

        input[0] = 32;
        input[1] = 32;
        input[2] = 32;
        input[3] = a;
        input[4] = power;
        input[5] = q_mod;

        assembly {
            ret := staticcall(gas(), 0x05, input, 0xc0, result, 0x20)
        }
        require(ret);

        return result[0];
    }

    function fr_div(uint256 a, uint256 b) internal view returns (uint256) {
        require(b != 0);
        return mulmod(a, fr_invert(b), q_mod);
    }

    function fr_mul_add(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return fr_add(fr_mul(a, b), c);
    }

    function fr_mul_add_pm(
        uint256[] memory m,
        uint256[] memory proof,
        uint256 t,
        uint256 opcode
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < 32; i += 2) {
            uint256 a = opcode & 0xff;
            if (a != 0xff) {
                opcode >>= 8;
                uint256 b = opcode & 0xff;
                opcode >>= 8;
                t = fr_add(fr_mul(proof[a], m[b]), t);
            } else {
                break;
            }
        }

        return t;
    }

    function fr_reverse(uint256 input) internal pure returns (uint256 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
            ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    uint256 constant p_mod =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct G1Point {
        uint256 x;
        uint256 y;
    }

    struct G2Point {
        uint256[2] x;
        uint256[2] y;
    }

    function ecc_from(uint256 x, uint256 y)
        internal
        pure
        returns (G1Point memory r)
    {
        r.x = x;
        r.y = y;
    }

    function ecc_is_identity(uint256 x, uint256 y) internal pure returns (bool) {
        return x == 0 && y == 0;
    }

    function ecc_add(uint256 ax, uint256 ay, uint256 bx, uint256 by)
        internal
        view
        returns (uint256, uint256)
    {
        if (ecc_is_identity(ax, ay)) {
            return (bx, by);
        } else if (ecc_is_identity(bx, by)) {
            return (ax, ay);
        } else {
            bool ret = false;
            G1Point memory r;
            uint256[4] memory input_points;

            input_points[0] = ax;
            input_points[1] = ay;
            input_points[2] = bx;
            input_points[3] = by;

            assembly {
                ret := staticcall(gas(), 6, input_points, 0x80, r, 0x40)
            }
            require(ret);

            return (r.x, r.y);
        }
    }

    function ecc_sub(uint256 ax, uint256 ay, uint256 bx, uint256 by)
        internal
        view
        returns (uint256, uint256)
    {
        return ecc_add(ax, ay, bx, p_mod - by);
    }

    function ecc_mul(uint256 px, uint256 py, uint256 s)
        internal
        view
        returns (uint256, uint256)
    {
        if (ecc_is_identity(px, py)) {
            return (px, py);
        } else {
            uint256[3] memory input;
            bool ret = false;
            G1Point memory r;

            input[0] = px;
            input[1] = py;
            input[2] = s;

            assembly {
                ret := staticcall(gas(), 7, input, 0x60, r, 0x40)
            }
            require(ret);

            return (r.x, r.y);
        }
    }

    function ecc_mul_add(uint256 px, uint256 py, uint256 s, uint256 qx, uint256 qy)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 x = 0;
        uint256 y = 0;
        (x, y) = ecc_mul(px, py, s);
        return ecc_add(x, y, qx, qy);
    }

    function update_hash_scalar(uint256 v, uint256[] memory absorbing, uint256 pos) internal pure {
        absorbing[pos++] = 0x02;
        absorbing[pos++] = v;
    }

    function update_hash_point(uint256 x, uint256 y, uint256[] memory absorbing, uint256 pos) internal pure {
        absorbing[pos++] = 0x01;
        absorbing[pos++] = x;
        absorbing[pos++] = y;
    }

    function to_scalar(bytes32 r) private pure returns (uint256 v) {
        uint256 tmp = uint256(r);
        tmp = fr_reverse(tmp);
        v = tmp % 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    }

    function hash(uint256[] memory data, uint256 length) private pure returns (bytes32 v) {
        uint256[] memory buf = new uint256[](length);
        uint256 i = 0;

        for (i = 0; i < length; i++) {
            buf[i] = data[i];
        }

        v = keccak256(abi.encodePacked(buf, uint8(0)));
    }

    function squeeze_challenge(uint256[] memory absorbing, uint32 length) internal pure returns (uint256 v) {
        bytes32 res = hash(absorbing, length);
        v = to_scalar(res);
        absorbing[0] = uint256(res);
        length = 1;
    }

    function get_g2_s() internal pure returns (G2Point memory s) {
        s.x[0] = uint256({{s_g2_x0}});
        s.x[1] = uint256({{s_g2_x1}});
        s.y[0] = uint256({{s_g2_y0}});
        s.y[1] = uint256({{s_g2_y1}});
    }

    function get_g2_n() internal pure returns (G2Point memory n) {
        n.x[0] = uint256({{n_g2_x0}});
        n.x[1] = uint256({{n_g2_x1}});
        n.y[0] = uint256({{n_g2_y0}});
        n.y[1] = uint256({{n_g2_y1}});
    }

    function get_wx_wg(uint256[] memory proof, uint256[] memory instances)
        internal
        view
        returns (G1Point[2] memory)
    {
        uint256[] memory m = new uint256[]({{memory_size}});
        uint256[] memory absorbing = new uint256[]({{absorbing_length}});
        uint256 t0 = 0;
        uint256 t1 = 0;

        {% for statement in statements %}
        {{statement}}
        {%- endfor %}
        return [ecc_from({{ wx }}), ecc_from({{ wg }})];
    }

    function verify(uint256[] memory proof, uint256[] memory instances) public view {
        // wx, wg
        G1Point[2] memory wx_wg = get_wx_wg(proof, instances);
        G1Point[] memory g1_points = new G1Point[](2);
        g1_points[0] = wx_wg[0];
        g1_points[1] = wx_wg[1];
        G2Point[] memory g2_points = new G2Point[](2);
        g2_points[0] = get_g2_s();
        g2_points[1] = get_g2_n();

        bool checked = pairing(g1_points, g2_points);
        require(checked);
    }
}
