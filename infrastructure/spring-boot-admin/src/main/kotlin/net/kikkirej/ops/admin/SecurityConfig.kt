package net.kikkirej.ops.admin

import de.codecentric.boot.admin.server.config.AdminServerProperties
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.core.GrantedAuthority
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.authority.mapping.GrantedAuthoritiesMapper
import org.springframework.security.oauth2.core.user.OAuth2UserAuthority
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.SavedRequestAwareAuthenticationSuccessHandler
import org.springframework.security.web.csrf.CookieCsrfTokenRepository
import org.springframework.security.web.util.matcher.AntPathRequestMatcher

@Configuration
@EnableWebSecurity
class SecurityConfig(private val adminServer: AdminServerProperties) {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        val successHandler = SavedRequestAwareAuthenticationSuccessHandler().apply {
            setTargetUrlParameter("redirectTo")
            setDefaultTargetUrl(adminServer.path("/"))
        }

        http
            .authorizeHttpRequests { auth ->
                auth
                    .requestMatchers(
                        AntPathRequestMatcher(adminServer.path("/actuator/health")),
                        AntPathRequestMatcher(adminServer.path("/actuator/info")),
                        AntPathRequestMatcher(adminServer.path("/login")),
                        AntPathRequestMatcher(adminServer.path("/assets/**")),
                        AntPathRequestMatcher(adminServer.path("/*.js")),
                        AntPathRequestMatcher(adminServer.path("/*.css"))
                    ).permitAll()
                    .anyRequest().hasRole("sba-admin")
            }
            .oauth2Login { oauth2 ->
                oauth2
                    .loginPage("/oauth2/authorization/keycloak")
                    .successHandler(successHandler)
            }
            .logout { logout ->
                logout
                    .logoutUrl(adminServer.path("/logout"))
                    .logoutSuccessUrl("/oauth2/authorization/keycloak")
            }
            .csrf { csrf ->
                csrf.csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                    .ignoringRequestMatchers(
                        AntPathRequestMatcher(adminServer.path("/instances"), "POST"),
                        AntPathRequestMatcher(adminServer.path("/instances/*"), "DELETE"),
                        AntPathRequestMatcher(adminServer.path("/actuator/**"))
                    )
            }

        return http.build()
    }

    @Bean
    fun keycloakRolesMapper(): GrantedAuthoritiesMapper = GrantedAuthoritiesMapper { authorities ->
        val mappedAuthorities = mutableSetOf<GrantedAuthority>()
        authorities.forEach { authority ->
            mappedAuthorities.add(authority)
            if (authority is OAuth2UserAuthority) {
                @Suppress("UNCHECKED_CAST")
                val realmRoles = (authority.attributes["roles"] as? Collection<String>) ?: emptyList()
                realmRoles.forEach { role ->
                    mappedAuthorities.add(SimpleGrantedAuthority("ROLE_$role"))
                }
            }
        }
        mappedAuthorities
    }
}
