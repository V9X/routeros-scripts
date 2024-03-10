# Simple script for updating IP in Cloudflare DNS record


# Cloudflare credentials.
:global cloudflareZoneId "zone_id";
:global cloudflareDnsId "dns_id";
:global cloudflareApiKey "api_key";

# Script configuration.
:global ddnsStop false;
:global previousIpFileName "previous-ip.txt";

# Runtime cache.
:local currentIp;
:local previousIp;

# Obtain the WAN IP address directly from the ether1 interface.
:local getCurrentIp do={
    :local ip;
    :while (true) do={
        :do {
            :set ip [/ip address get [find interface="ether1"] address];
            :set ip [:pick $ip 0 ([:len $ip] - 3)];

            :return $ip;
        } on-error={
            :log error "Could not obtain an IP address. 'ether1' interface not found";
            :delay 1m;
        };
    };
};

# Write to a file. If it does not exist, create a new one. 
# This function assumes writing to the file will only fail if the file does not exist.
:local writePreviousIp do={
    :log info "Writing previous IP: '$content' to the file";

    :do {
        /file set $name contents=$content;
    } on-error={
        :log error "Failed to write to the file: '$name', creating new one";
        /file add name=$name contents=$content;
    }
}




# Load previous IP from file.
:do {
    :set $previousIp [/file get $previousIpFileName contents];
} on-error={
    $writePreviousIp name=$previousIpFileName content=[$getCurrentIp];
};

:log info "Starting, previous IP: '$previousIp'";

while (!$ddnsStop) do={
    :set $currentIp [$getCurrentIp];

    :if ($currentIp != $previousIp) do={
        :log info "WAN IP changed. Previous: '$previousIp', current: '$currentIp'.";

        :do {
            # https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-update-dns-record
            # 200 - Alaways on success.
            :local result [/tool fetch \
                url="https://api.cloudflare.com/client/v4/zones/$cloudflareZoneId/dns_records/$cloudflareDnsId" \
                http-header-field="Authorization: Bearer $cloudflareApiKey" \
                http-data="{\"content\":\"$currentIp\",\"name\":\"@\",\"type\":\"A\"}" \
                http-method=put \
                mode=https \
                as-value \
                output=user
            ];

            :local data ($result->"data");

            :log info "Succes: $data";

            # At this point, everything should have been executed successfully.
            # Therefore, we overwrite the previous IP with the new one.
            $writePreviousIp name=$previousIpFileName content=$currentIp;
            :set $previousIp $currentIp;
        } on-error={
            :log error "Failure"
            :delay 1m;
        }
    }

   :delay 30s;
};